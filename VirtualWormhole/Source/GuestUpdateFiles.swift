import Foundation
import CryptoKit
import Security

/// File work runs off the UI actor. Each subprocess has an independent owner.
public enum GuestUpdateFiles {
    public static func createImage(appURL: URL) async throws -> (URL, GuestAppUpdatePackage) {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GuestUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let contents = directory.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
            let app = contents.appendingPathComponent("VirtualBuddyGuest.app")
            try FileManager.default.copyItem(at: appURL, to: app)
            guard let bundle = Bundle(url: app) else { throw GuestAppUpdateError.invalidPackage }
            let identity = try GuestAppIdentity(bundle: bundle)
            let image = directory.appendingPathComponent("VirtualBuddyGuest-Update.dmg")
            try await GuestUpdateCommand().run("/usr/bin/hdiutil", [
                "create", "-srcfolder", contents.path, "-volname", "VirtualBuddyGuest Update",
                "-format", "UDZO", image.path
            ])
            try FileManager.default.removeItem(at: contents)
            let (size, hash) = try digest(image)
            guard size > 0, size <= GuestAppUpdatePackage.maximumBytes else { throw GuestAppUpdateError.invalidPackage }
            return (image, GuestAppUpdatePackage(identity: identity, byteCount: size, sha256: hash))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    public static func exportImage(appURL: URL, to destination: URL) async throws {
        let (image, _) = try await createImage(appURL: appURL)
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }
        try await exportExistingImage(image, to: destination)
    }

    public static func exportExistingImage(_ image: URL, to destination: URL) async throws {
        // Stage beside the destination so replacing an existing export is atomic.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".GuestInstaller-\(UUID().uuidString).dmg")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: image, to: staging)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }

    public static func verify(_ image: URL, package: GuestAppUpdatePackage) async throws {
        guard package.byteCount > 0, package.byteCount <= GuestAppUpdatePackage.maximumBytes else {
            throw GuestAppUpdateError.invalidPackage
        }
        let (size, hash) = try digest(image)
        guard size == package.byteCount, hash == package.sha256 else { throw GuestAppUpdateError.invalidPackage }
    }

    private static func digest(_ url: URL) throws -> (Int64, Data) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var size: Int64 = 0
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            size += Int64(chunk.count)
            guard size <= GuestAppUpdatePackage.maximumBytes else { throw GuestAppUpdateError.invalidPackage }
            digest.update(data: chunk)
        }
        return (size, Data(digest.finalize()))
    }

    /// Both bundles must live on the same volume. The installed path is never absent,
    /// even if the machine loses power during replacement or rollback.
    public static func exchangeApplications(_ first: URL, _ second: URL) throws {
        let result = first.withUnsafeFileSystemRepresentation { firstPath in
            second.withUnsafeFileSystemRepresentation { secondPath in
                renameatx_np(AT_FDCWD, firstPath!, AT_FDCWD, secondPath!, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    /// Validate the complete bundle, including nested code, against the installed app's signing requirement.
    public static func validateApplication(at candidate: URL, replacing current: URL, expected: GuestAppIdentity) throws {
        guard try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false,
              try current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false,
              let bundle = Bundle(url: candidate), let installed = Bundle(url: current),
              bundle.bundleIdentifier == installed.bundleIdentifier,
              try GuestAppIdentity(bundle: bundle) == expected else { throw GuestAppUpdateError.invalidPackage }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard expected.supports(osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"),
              expected.build >= (try GuestAppIdentity(bundle: installed)).build else { throw GuestAppUpdateError.unsupported }
        var currentCode: SecStaticCode?
        var candidateCode: SecStaticCode?
        try GuestAppIdentity.check(SecStaticCodeCreateWithPath(current as CFURL, [], &currentCode))
        try GuestAppIdentity.check(SecStaticCodeCreateWithPath(candidate as CFURL, [], &candidateCode))
        guard let currentCode, let candidateCode else { throw GuestAppUpdateError.invalidPackage }
        var requirement: SecRequirement?
        try GuestAppIdentity.check(SecCodeCopyDesignatedRequirement(currentCode, [], &requirement))
        guard let requirement else { throw GuestAppUpdateError.invalidPackage }
        try GuestAppIdentity.check(SecStaticCodeCheckValidity(candidateCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures), requirement))
    }
}

/// Uses files for output, avoiding pipe-buffer deadlocks, and terminates on cancellation.
public actor GuestUpdateCommand {
    private var process: Process?
    public init() { }

    public func run(_ executable: String, _ arguments: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.execute(executable, arguments) }
            group.addTask {
                try await Task.sleep(for: .seconds(120))
                throw GuestAppUpdateError.interrupted
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func execute(_ executable: String, _ arguments: [String]) async throws {
        try Task.checkCancellation()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let command = Process()
        command.executableURL = URL(fileURLWithPath: executable)
        command.arguments = arguments
        command.standardInput = FileHandle.nullDevice
        command.standardOutput = handle
        command.standardError = handle
        process = command
        defer { process = nil; command.terminationHandler = nil }
        let status: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                command.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try command.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
        try Task.checkCancellation()
        guard status == 0 else {
            let reader = try FileHandle(forReadingFrom: output)
            defer { try? reader.close() }
            let reason = String(decoding: try reader.read(upToCount: 4096) ?? Data(), as: UTF8.self)
            throw NSError(domain: "GuestUpdateCommand", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "The guest update could not be prepared. \(reason)"
            ])
        }
    }

    private func cancel() {
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
