import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

let kGuestPingServiceID = "codes.rambo.VirtualBuddy.PingService"

public final class GuestPingService: GuestService, @unchecked Sendable {
    private let logger = Logger(subsystem: kVirtualMessagingSubsystem, category: "GuestPingService")

    public override var id: String { kGuestPingServiceID }

    public override func bootstrapCompleted() {
        logger.debug(#function)

        register(handlePing)
    }

    @Sendable private func handlePing(_ ping: VMPingPayload, peer: VMPeerConnection) async throws {
        logger.debug("Received ping: \(String(describing: ping))")

        try await peer.send(VMPongPayload(id: ping.id))

        logger.debug("Successfully replied to ping")
    }
}
