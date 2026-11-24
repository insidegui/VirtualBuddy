import Foundation

/// A connection to a selected, authorized destination. One session is used per run.
/// The transport owns peer authentication, file delivery, and opening its duplex channel.
@MainActor
public protocol RemoteDebugSession: AnyObject, Sendable {
    func prepareDebugRun(_ run: UUID) async throws -> DebugSystemImages
    func provisioningUDID(for run: UUID) async throws -> String
    func transferDebugImage(_ file: DebugSystemImages.File, run: UUID, to destination: URL) async throws
    func launch(_ archive: URL, options: DebugLaunchOptions, run: UUID) async throws -> (bundlePath: String, stream: DebugSocket)
    func cancelDebugRun(_ run: UUID) async
}
