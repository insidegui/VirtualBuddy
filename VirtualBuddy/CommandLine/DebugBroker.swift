import Foundation
import MacDebugHost
import MacDebugProtocol
import VirtualCore
import VirtualUI
import VirtualWormhole
import Virtualization

@MainActor
extension DebugBroker {
    convenience init(library: VMLibraryController) {
        self.init(configuration: VirtualBuddyDebugging.host, cache: VirtualBuddyDebugging.symbolCache) {
            try VBSettings.current.requireDeveloperFeatures()
        } resolveDestination: { id in
            try await VMDebugSession(destination: id, library: library)
        }
    }
}

@MainActor
private final class VMDebugSession: RemoteDebugSession {
    private let controller: VMController
    private let session: HostGuestSession
    private var connection: VZVirtioSocketConnection?

    init(destination: UUID, library: VMLibraryController) async throws {
        let ui = try await VirtualMachineSessionUIManager.shared.sessionForDebugging(destination, library: library)
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while ui.controller.debugGuestSession?.isConnected != true {
            guard ui.controller.state.isRunning, ContinuousClock.now < deadline else {
                throw MacDebugError("Log in to the VM and open the current VirtualBuddyGuest app, then run again.")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard let session = ui.controller.debugGuestSession, session.supportsDebugging else {
            throw MacDebugError("Install the current VirtualBuddyGuest from the guest additions disk and open it in the VM.")
        }
        self.controller = ui.controller
        self.session = session
    }

    func prepareDebugRun(_ run: UUID) async throws -> DebugSystemImages {
        try await session.prepareDebugRun(run)
    }

    func transferDebugImage(_ file: DebugSystemImages.File, run: UUID, to destination: URL) async throws {
        try await session.transferDebugImage(file, run: run, to: destination)
    }

    func launch(_ archive: URL, options: DebugLaunchOptions, run: UUID) async throws -> (bundlePath: String, stream: DebugSocket) {
        let endpoint = try await session.launchDebugApp(archive, options: options, run: run)
        let connection = try await controller.connectDebugger(to: endpoint.port)
        let remote = try DebugSocket(owning: dup(connection.fileDescriptor))
        let token = try await withThrowingTaskGroup(of: UUID.self) { group in
            group.addTask { try await remote.receive(UUID.self) }
            group.addTask { try await Task.sleep(for: .seconds(10)); throw POSIXError(.ETIMEDOUT) }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        guard token == run else { throw MacDebugError("Unexpected debugger session from the VM.") }
        self.connection = connection
        return (endpoint.bundlePath, remote)
    }

    func cancelDebugRun(_ run: UUID) async {
        await session.cancelDebugRun(run)
        connection = nil
    }
}
