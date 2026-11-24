import Foundation
import os

public enum DebugTools {
    /// Keep blocking tools and waitpid off the UI actor. Termination and launch are
    /// serialized so cancellation between registration and spawn cannot lose the child.
    public static func run(_ url: URL, _ arguments: [String], standardOutput: Pipe? = nil,
                           log: FileHandle? = nil, environment: [String: String]? = nil) async throws {
        // Readers must also receive EOF when launch fails or is cancelled.
        defer { try? standardOutput?.fileHandleForWriting.close() }
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.environment = environment
        if let log {
            process.standardOutput = log
            process.standardError = log
        }
        if let standardOutput { process.standardOutput = standardOutput }
        let queue = DispatchQueue(label: "MacDebug.tool")
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
                        else { result.resume(throwing: MacDebugError("\(url.lastPathComponent) exited with status \(child.terminationStatus).")) }
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

    /// Large deployed bundles and temporary archives are also removed off the main actor.
    public static func withTemporaryDirectory<T: Sendable>(_ operation: @Sendable (URL) async throws -> T) async throws -> T {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try directory(work)
        defer { try? FileManager.default.removeItem(at: work) }
        return try await operation(work)
    }
}
