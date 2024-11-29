import Cocoa
import SwiftUI
import VirtualUI
import VirtualCore
import OSLog

final class GuestAppServices {
    private let logger = Logger(subsystem: kGuestAppSubsystem, category: "GuestAppServices")

    static let shared = GuestAppServices()

    let coordinator: GuestServerCoordinator

    let ping = GuestPingService()

    private var services: [GuestService] {
        [ping]
    }

    private init() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "GuestSimulationEnabled") {
            logger.info("Using simulated guest coordination server")

            coordinator = .simulatedGuest
        } else {
            coordinator = .virtualizedGuest
        }
        #else
        coordinator = .virtualizedGuest
        #endif
    }

    func activate() {
        logger.debug(#function)

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
