import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

public final class GuestPingClient: GuestService, @unchecked Sendable {
    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "GuestPingClient")

    public override var id: String { kGuestPingServiceID }

    public override func bootstrapCompleted() {
        logger.debug(#function)
    }

    @Sendable private func handlePong(_ pong: VMPongPayload, peer: VMPeerConnection) async throws {
        logger.debug("Received pong: \(String(describing: pong))")
    }

    @discardableResult
    public func sendPing() async throws -> VMPongPayload {
        try await sendWithReply(VMPingPayload())
    }
}
