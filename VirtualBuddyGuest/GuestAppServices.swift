import Cocoa
import SwiftUI
import VirtualUI
import VirtualCore
import OSLog

final class GuestAppServices: ObservableObject, HostConnectionStateProvider {
    private let logger = Logger(subsystem: kGuestAppSubsystem, category: "GuestAppServices")

    static let shared = GuestAppServices()

    let coordinator = GuestServicesCoordinator.current

    let ping = GuestPingService()
    let clipboard = GuestClipboardService()

    private var services: [GuestService] {
        [ping, clipboard]
    }

    private init() { }

    @MainActor
    @Published public private(set) var hasConnection = false

    @MainActor
    func activate() {
        logger.debug(#function)

        coordinator.$hasConnection.assign(to: &$hasConnection)

        Task.detached(priority: .high) { [self] in
            do {
                try await coordinator.activate()

                await bootstrapServices()
            } catch {
                self.logger.error("Guest coordination server activation failed. \(error, privacy: .public)")

                await NSAlert(error: error).runModal()
            }
        }
    }

    private func bootstrapServices() async {
        await withThrowingTaskGroup(of: Void.self) { [self] group in
            for service in services {
                group.addTask { [self] in
                    do {
                        try await coordinator.bootstrap(service: service)
                    } catch {
                        logger.error("Failed to boostrap \(service.shortID, privacy: .public). \(error, privacy: .public)")
                    }
                }
            }
        }
    }
}
