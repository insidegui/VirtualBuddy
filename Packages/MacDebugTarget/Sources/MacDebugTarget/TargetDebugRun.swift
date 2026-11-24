import Foundation
import MacDebugProtocol

/// The target half of one authorized debug run. The adapter delivers the archive,
/// serves only the advertised images, and supplies an authenticated debugger stream.
@MainActor
public final class TargetDebugRun {
    public let id: UUID
    public let images: DebugSystemImages
    public let archiveURL: URL
    private let files: [String: URL]
    private let directory: URL
    private let debugger: URL
    private var installing = false
    private var installedApp: (bundle: URL, executable: URL)?
    private var cancelled = false
    private var child: Process?

    public init(id: UUID, storageRoot: URL) throws {
        self.id = id
        debugger = try TargetDebugTools.debugger()
        (images, files) = try DebugSystemImages.collect()
        try DebugTools.directory(storageRoot)
        // A retried run can reuse its wire ID while a cancelled transfer is draining.
        let staging = storageRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = staging
        archiveURL = staging.appendingPathComponent("Application.zip")
    }

    public func imageURL(named name: String) throws -> URL {
        guard !cancelled, let file = files[name] else { throw MacDebugError("Unknown debug system image.") }
        return file
    }

    /// Call after delivery of the complete archive. Returns the installed bundle path for LLDB.
    public func install() async throws -> URL {
        guard !cancelled, !installing, installedApp == nil else { throw MacDebugError("This debug run cannot install another application.") }
        installing = true
        defer { installing = false }
        let app = try await TargetDebugTools.install(archiveURL, into: directory)
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        installedApp = app
        return app.0
    }

    public func serve(over stream: DebugSocket, options: DebugLaunchOptions) async throws {
        try Task.checkCancellation()
        guard !cancelled, let app = installedApp, child == nil else { throw MacDebugError("This debug run is unavailable.") }
        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw POSIXError(.EIO) }
        let input = FileHandle(fileDescriptor: pair[1], closeOnDealloc: true)
        let relay = try DebugSocket(owning: pair[0])
        let process = Process()
        process.executableURL = debugger
        process.currentDirectoryURL = app.bundle.deletingLastPathComponent()
        let environment = options.environment.sorted { $0.key < $1.key }.flatMap { ["-e", "\($0.key)=\($0.value)"] }
        // Terminate debugserver's options before any developer-supplied arguments.
        process.arguments = ["--fd=0", "--kill-on-error"] + environment + ["--", app.executable.path] + options.arguments
        process.standardInput = input
        try process.run()
        child = process
        defer { cancel() }
        try input.close()
        await DebugSocket.relay(stream, relay)
    }

    public func cancel() {
        cancelled = true
        if let child, child.isRunning { child.terminate() }
        child = nil
    }

    /// Release the run after all transport tasks using archiveURL have finished.
    deinit { try? FileManager.default.removeItem(at: directory) }
}
