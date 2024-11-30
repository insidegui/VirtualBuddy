import Foundation
import OSLog

public final class HostAppServices: ObservableObject {
    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "HostAppServices")

    let coordinator: GuestServicesCoordinator

    public init(coordinator: GuestServicesCoordinator) {
        self.coordinator = coordinator
    }

    #if DEBUG
    /// [DEBUG ONLY] Shared instance for guest simulation.
    public static let guestSimulator = HostAppServices(coordinator: .simulatedHostClient)
    #endif

    public let ping = GuestPingClient()
    public let clipboard = GuestClipboardService()

    private var serviceClients: [GuestService] {
        [ping, clipboard]
    }

    @MainActor
    @Published public private(set) var hasConnection = false

    @MainActor
    @discardableResult
    public func activate() -> Self {
        logger.debug(#function)

        coordinator.$hasConnection.assign(to: &$hasConnection)

        Task.detached(priority: .high) { [self] in
            do {
                try await coordinator.activate()

                await bootstrapServiceClients()
            } catch {
                self.logger.error("Host coordination service activation failed. \(error, privacy: .public)")

                await NSAlert(error: error).runModal()
            }
        }

        return self
    }

    private func bootstrapServiceClients() async {
        await withThrowingTaskGroup(of: Void.self) { [self] group in
            for serviceClient in serviceClients {
                group.addTask { [self] in
                    do {
                        try await coordinator.bootstrap(service: serviceClient)
                    } catch {
                        logger.error("Failed to boostrap \(serviceClient.shortID, privacy: .public). \(error, privacy: .public)")
                    }
                }
            }
        }
    }
}
