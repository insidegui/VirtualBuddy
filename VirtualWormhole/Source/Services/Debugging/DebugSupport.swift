import Foundation
import Security
import os

public struct VBDebugError: LocalizedError, Sendable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public struct DebugLaunchOptions: Codable, Sendable {
    public let arguments: [String]
    public let environment: [String: String]
    public init(arguments: [String], environment: [String: String]) {
        self.arguments = arguments
        self.environment = environment
    }
}

public struct DebugSystemImages: Codable, Sendable {
    public struct File: Codable, Sendable {
        public let name: String
        public let bytes: Int64
    }
    public let version: String
    public let build: String
    public let architecture: String
    public let uuid: UUID
    public let files: [File]
    public var primary: String { "dyld_shared_cache_\(architecture)" }

    public func validate() throws {
        let digits = CharacterSet(charactersIn: "0123456789.")
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        func valid(_ value: String, _ allowed: CharacterSet) -> Bool {
            (1...100).contains(value.utf8.count) && value.unicodeScalars.allSatisfy(allowed.contains)
        }
        guard valid(version, digits), valid(build, letters), ["arm64", "arm64e"].contains(architecture),
              Set(files.map(\.name)).count == files.count, files.count < 256,
              files.contains(where: { $0.name == primary }), files.contains(where: { $0.name == "dyld" }),
              files.allSatisfy({ file in
                  file.bytes > 0 && file.bytes <= 32 << 30 && (file.name == "dyld" || file.name == primary ||
                    (file.name.hasPrefix(primary + ".") && valid(String(file.name.dropFirst(primary.count + 1)), letters.union(digits))))
              }) else { throw VBDebugError("The guest reported an invalid system image set.") }
    }

    static func collect() throws -> (Self, [String: URL]) {
        let fm = FileManager.default
        for directory in ["/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld", "/System/Library/dyld"] {
            let folder = URL(fileURLWithPath: directory)
            guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for arch in ["arm64e", "arm64"] {
                let primary = "dyld_shared_cache_" + arch
                guard let cache = contents.first(where: { $0.lastPathComponent == primary }) else { continue }
                let handle = try FileHandle(forReadingFrom: cache)
                defer { try? handle.close() }
                guard let header = try handle.read(upToCount: 104), header.count == 104,
                      header.starts(with: Data("dyld_v1".utf8)) else { throw VBDebugError("Unknown dyld cache format.") }
                let uuid = header.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(fromByteOffset: 88, as: uuid_t.self)) }
                var urls = ["dyld": URL(fileURLWithPath: "/usr/lib/dyld")]
                for file in contents where file.lastPathComponent == primary || file.lastPathComponent.hasPrefix(primary + ".") {
                    urls[file.lastPathComponent] = file
                }
                let system = try NSDictionary(contentsOf: URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"), error: ())
                guard let build = system["ProductBuildVersion"] as? String, let version = system["ProductVersion"] as? String else {
                    throw VBDebugError("Could not identify this version of macOS.")
                }
                let files = try urls.sorted { $0.key < $1.key }.map { name, url in
                    File(name: name, bytes: Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0))
                }
                let images = Self(version: version, build: build, architecture: arch, uuid: uuid, files: files)
                try images.validate()
                return (images, urls)
            }
        }
        throw VBDebugError("Could not locate the guest’s dyld shared cache.")
    }
}

public enum DebugTools {
    /// Keep blocking tools and waitpid off the UI actor. Termination and launch are
    /// serialized so cancellation between registration and spawn cannot lose the child.
    public static func run(_ url: URL, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let queue = DispatchQueue(label: "VirtualBuddy.debug.tool")
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (result: CheckedContinuation<Void, Error>) in
                queue.async {
                    guard !cancelled.withLock({ $0 }) else {
                        result.resume(throwing: CancellationError())
                        return
                    }
                    process.terminationHandler = { child in
                        if cancelled.withLock({ $0 }) { result.resume(throwing: CancellationError()) }
                        else if child.terminationStatus == 0 { result.resume() }
                        else { result.resume(throwing: VBDebugError("\(url.lastPathComponent) exited with status \(child.terminationStatus).")) }
                    }
                    do { try process.run() } catch { result.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
        } onCancel: {
            cancelled.withLock { $0 = true }
            queue.async { if process.isRunning { process.terminate() } }
        }
    }

    public static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    static func debugger() throws -> URL {
        let candidates = ["/Library/Developer/CommandLineTools/Library/PrivateFrameworks/LLDB.framework/Resources/debugserver"] +
            ((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []).sorted().filter { $0.hasSuffix(".app") && $0.hasPrefix("Xcode") }.map {
                "/Applications/" + $0 + "/Contents/SharedFrameworks/LLDB.framework/Resources/debugserver"
            }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            var code: SecStaticCode?
            var requirement: SecRequirement?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
                  SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
                  SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { continue }
            return url
        }
        throw VBDebugError("Install Apple’s Command Line Tools or Xcode in the guest to provide debugserver.")
    }

    static func install(_ archive: URL, into staging: URL) async throws -> (URL, URL) {
        let fm = FileManager.default
        let unpack = staging.appendingPathComponent("Unpacked")
        try directory(unpack)
        try await run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, unpack.path])
        let apps = try fm.contentsOfDirectory(at: unpack, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let source = apps.first, let bundle = Bundle(url: source),
              let id = bundle.bundleIdentifier, !id.isEmpty, id.utf8.count < 256,
              id.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil,
              let executable = bundle.executableURL, source.resolvingSymlinksInPath().deletingLastPathComponent().path == unpack.resolvingSymlinksInPath().path,
              executable.resolvingSymlinksInPath().path.hasPrefix(source.resolvingSymlinksInPath().path + "/"),
              bundle.executableArchitectures?.contains(NSNumber(value: CPU_TYPE_ARM64)) == true else {
            throw VBDebugError("Build an arm64 macOS app for the selected VM.")
        }
        if let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            guard minimum.compare("\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)", options: .numeric) != .orderedDescending else {
                throw VBDebugError("This app requires macOS \(minimum) or later.")
            }
        }
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(source as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let entitlements = (info as NSDictionary?)?[kSecCodeInfoEntitlementsDict] as? [String: Any],
              entitlements["com.apple.security.get-task-allow"] as? Bool == true else {
            throw VBDebugError("Build a signed Debug app with the com.apple.security.get-task-allow entitlement.")
        }
        let folder = staging.deletingLastPathComponent().appendingPathComponent("Apps").appendingPathComponent(id)
        try directory(folder)
        let dest = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            guard renamex_np(source.path, dest.path, UInt32(RENAME_SWAP)) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        } else { try fm.moveItem(at: source, to: dest) }
        return (dest, dest.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable.lastPathComponent))
    }
}
