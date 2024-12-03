import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

let kGuestAppearanceServiceID = "codes.rambo.VirtualBuddy.AppearanceService"

public final class GuestAppearanceService: GuestService, @unchecked Sendable {
    private let logger = Logger(subsystem: kVirtualMessagingSubsystem, category: "GuestAppearanceService")

    public override var id: String { kGuestAppearanceServiceID }

    public override func bootstrapCompleted() {
        logger.debug(#function)

        register { [weak self] in
            await self?.handleAppearanceChange($0, peer: $1)
        }
    }

    public override func connected(_ connection: VMPeerConnection) {
        super.connected(connection)

        performInitialAppearanceSync()
    }

    private func setAppearance(_ appearance: VMSystemAppearance) {
        guard !UserDefaults.isGuestSimulationEnabled else {
            logger.info("Ignoring appearance change to \(appearance) because guest simulation is enabled.")
            return
        }

        VMSystemAppearance.current = appearance
    }

    @Sendable private func handleAppearanceChange(_ payload: VMAppearanceChangePayload, peer: VMPeerConnection) async {
        logger.debug("Change appearance requested: \(String(describing: payload))")

        setAppearance(payload.appearance)
    }

    private func performInitialAppearanceSync() {
        logger.debug(#function)
        Task {
            do {
                let response: VMHostAppearanceResponse = try await sendWithReply(VMHostAppearanceRequest())

                logger.debug("Host responded with appearance: \(response.appearance)")

                setAppearance(response.appearance)
            } catch {
                logger.error("Initial appearance sync failed. \(error, privacy: .public)")
            }
        }
    }
}
