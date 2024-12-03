import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

public final class GuestAppearanceClient: GuestService, GuestServiceClient, @unchecked Sendable {
    private let logger = Logger(subsystem: kVirtualMessagingSubsystem, category: "GuestAppearanceClient")

    public override var id: String { kGuestAppearanceServiceID }

    private var observer: Any?

    public override func bootstrapCompleted() {
        logger.debug(#function)

        register { [weak self] in
            try await self?.handleAppearanceRequest($0, peer: $1)
        }
    }

    public override func connected(_ connection: VMPeerConnection) {
        super.connected(connection)

        observer = VMSystemAppearance.addObserver { [weak self] appearance in
            self?.sendAppearance(appearance)
        }
    }

    public override func disconnected(_ connection: VMPeerConnection) {
        super.disconnected(connection)

        VMSystemAppearance.removeObserver(observer)
        observer = nil
    }

    private func sendAppearance(_ appearance: VMSystemAppearance) {
        logger.debug("Sending appearance change with \(appearance)")

        Task {
            do {
                let payload = VMAppearanceChangePayload(appearance: appearance)
                try await send(payload)
            } catch {
                logger.error("Appearance change send failure. \(error, privacy: .public)")
            }
        }
    }

    @Sendable private func handleAppearanceRequest(_ request: VMHostAppearanceRequest, peer: VMPeerConnection) async throws {
        let response = VMHostAppearanceResponse(id: request.id, appearance: .current)

        logger.debug("Guest requested host appearance, sending \(response.appearance)")

        try await peer.send(response)
    }
}
