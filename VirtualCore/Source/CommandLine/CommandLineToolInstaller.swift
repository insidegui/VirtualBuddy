import Darwin
import Foundation
import OSLog

/// Links the `vbctl` command-line tool, which lives inside the app bundle, into a folder on the user's `PATH`.
///
/// Only folders the user can already write to are used, so installing never asks for an administrator password.
/// When there's no such folder, the user gets a command to run instead.
public struct CommandLineToolInstaller: Sendable {
    public static let toolName = "vbctl"

    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed(URL)
    }

    /// Thrown when the tool can't be linked without the user's help.
    public struct ManualInstallationRequired: LocalizedError, Equatable {
        /// A command that links the tool, for the user to run in Terminal.
        public let command: String

        public var errorDescription: String? {
            "None of the folders in your PATH can be written to without an administrator password."
        }
    }

    /// The tool inside the app bundle, which is what the link points to.
    var toolURL: URL
    /// Folders to link the tool into, in order of preference. Only the ones in the user's `PATH` are used.
    var candidates: [URL]
    /// The folders in the `PATH` of the user's shell.
    var searchPath: @Sendable () async -> [String]
    var defaults: @Sendable () -> UserDefaults

    private static let locationKey = "CommandLineToolInstallLocation"
    private static let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "CommandLineToolInstaller")

    public static var current: Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self(
            toolURL: bundledToolURL,
            candidates: [
                URL(fileURLWithPath: "/opt/homebrew/bin"),
                URL(fileURLWithPath: "/usr/local/bin"),
                home.appendingPathComponent(".local/bin"),
                home.appendingPathComponent("bin")
            ],
            searchPath: { await LoginShell.searchPath() },
            defaults: { .standard }
        )
    }

    /// Where the tool is inside the running app's bundle.
    public static var bundledToolURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(toolName)
    }

    /// The command that runs the tool without installing it.
    public var toolPath: String { toolURL.path }

    public func status() -> Status {
        guard let location = recordedLocation, destination(ofLinkAt: location) == toolURL.path else { return .notInstalled }
        return .installed(location)
    }

    /// Links the tool into the first folder in the user's `PATH` that can be written to, and returns the link.
    @discardableResult
    public func install() async throws -> URL {
        let path = Set(await searchPath().map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let usable = candidates.filter { path.contains($0.standardizedFileURL.path) }

        for directory in usable {
            let link = directory.appendingPathComponent(Self.toolName)
            do {
                try prepare(directory)
                guard canReplace(link) else {
                    Self.logger.notice("Not replacing \(link.path, privacy: .public) because VirtualBuddy didn't create it")
                    continue
                }
                try replaceLink(at: link)
                if let previous = recordedLocation, previous != link { removeLink(at: previous) }
                defaults().set(link.path, forKey: Self.locationKey)
                return link
            } catch {
                Self.logger.notice("Could not link the command-line tool into \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        throw ManualInstallationRequired(command: manualCommand)
    }

    public func uninstall() {
        guard let location = recordedLocation else { return }
        removeLink(at: location)
        defaults().removeObject(forKey: Self.locationKey)
    }

    /// Points the installed link at the app again after the app was moved or replaced by one somewhere else.
    public func repairIfNeeded() {
        guard let location = recordedLocation, let current = destination(ofLinkAt: location), current != toolURL.path else { return }
        do {
            try replaceLink(at: location)
            Self.logger.notice("Updated the command-line tool link at \(location.path, privacy: .public)")
        } catch {
            Self.logger.error("Could not update the command-line tool link at \(location.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    var manualCommand: String {
        "sudo mkdir -p /usr/local/bin && sudo ln -sf \(Self.shellQuoted(toolURL.path)) /usr/local/bin/\(Self.toolName)"
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private var recordedLocation: URL? {
        defaults().string(forKey: Self.locationKey).map { URL(fileURLWithPath: $0) }
    }

    /// Where the link leads, or `nil` when there's no link there. The destination doesn't have to exist.
    private func destination(ofLinkAt url: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    /// A link is only replaced when it leads to the tool in a copy of the app, which is what this installer creates.
    private func canReplace(_ link: URL) -> Bool {
        var info = stat()
        guard lstat(link.path, &info) == 0 else { return errno == ENOENT }
        guard let destination = destination(ofLinkAt: link) else { return false }
        return destination.hasSuffix(".app/Contents/MacOS/\(Self.toolName)")
    }

    /// Folders in the user's home folder are created when they're in the `PATH` but don't exist yet.
    private func prepare(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, FileManager.default.isWritableFile(atPath: directory.path) else { throw CocoaError(.fileWriteNoPermission) }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            guard directory.standardizedFileURL.path.hasPrefix(home + "/") else { throw CocoaError(.fileNoSuchFile) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// The new link takes the place of the old one in a single step, so the command never goes missing.
    private func replaceLink(at link: URL) throws {
        let temporary = link.deletingLastPathComponent().appendingPathComponent(".\(Self.toolName)-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: temporary.path, withDestinationPath: toolURL.path)
        guard rename(temporary.path, link.path) == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            unlink(temporary.path)
            throw error
        }
    }

    private func removeLink(at link: URL) {
        guard canReplace(link), destination(ofLinkAt: link) != nil else { return }
        unlink(link.path)
    }
}

/// Reads settings from the user's shell, which a graphical app doesn't inherit.
enum LoginShell {
    /// The folders in the `PATH` that the user's shell sets up for a terminal session.
    static func searchPath() async -> [String] {
        let fallback = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        guard let shell = userShell else { return fallback }

        // The shell's startup files can print anything, so the value is picked out between two markers.
        let marker = UUID().uuidString
        let process = Process()
        process.executableURL = shell
        process.arguments = ["-l", "-i", "-c", "printf '%s%s%s' '\(marker)' \"$PATH\" '\(marker)'"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
        } catch {
            return fallback
        }

        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            process.terminate()
        }
        defer { timeout.cancel() }

        let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        let parts = String(decoding: data, as: UTF8.self).components(separatedBy: marker)
        guard parts.count == 3, !parts[1].isEmpty else { return fallback }
        return parts[1].split(separator: ":").map(String.init)
    }

    private static var userShell: URL? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        let path = String(cString: shell)
        return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}
