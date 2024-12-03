import Foundation
import OSLog
import VirtualMessagingService

public typealias HostAppServiceClient = GuestService & GuestServiceClient

public final class HostAppServices: ObservableObject {
    private let logger = Logger(subsystem: kVirtualMessagingSubsystem, category: "HostAppServices")

    let coordinator: GuestServicesCoordinator

    public init(coordinator: GuestServicesCoordinator) {
        self.coordinator = coordinator
    }

    #if DEBUG
    /// [DEBUG ONLY] Shared instance for guest simulation.
    public static var guestSimulator: HostAppServices { HostAppServices(coordinator: .simulatedHostClient) }
    #endif

    public let ping = GuestPingClient()
    public let clipboard = GuestClipboardClient()
    public let appearance = GuestAppearanceClient()

    private var serviceClients: [HostAppServiceClient] {
        [ping, clipboard, appearance]
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

    deinit {
        #if DEBUG
        print("[SERVICES] Bye bye 👋")
        #endif
    }
}
