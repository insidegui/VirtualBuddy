import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

let kGuestNotificationCenterServiceID = "codes.rambo.VirtualBuddy.NotificationCenterService"

public class GuestNotificationCenterService: GuestService, @unchecked Sendable {
    let logger = Logger(subsystem: kVirtualMessagingSubsystem, category: "GuestNotificationCenterService")

    public override var id: String { kGuestNotificationCenterServiceID }

    var isGuest: Bool { true }

    private let observer = NotificationCenterObserver()

    @MainActor
    private var keysByPeerID = [VMPeerConnection.ID: [NotificationCenterObserver.Key]]()

    /// Remote notifications the local peer is observing from the remote peer.
    /// This is used to match a received notification payload with the associated callback.
    @MainActor
    private var callbacksByRegistrationID = [UUID: @MainActor (String) -> Void]()

    private var observerTask: Task<Void, Never>?

    public override func bootstrapCompleted() {
        logger.debug(#function)

        register { [weak self] in
            await self?.handleRegistration($0, peer: $1)
        }
        register { [weak self] in
            await self?.handleNotification($0, peer: $1)
        }
    }

    @MainActor
    public func addObserver(for name: String, type: NotificationCenterType, using callback: @escaping @MainActor (String) -> Void) async throws {
        logger.debug("Adding observer for \(type.rawValue):\(name)")

        let payload = VMNotificationRegistrationPayload(type: type, name: name)

        try await send(payload)

        callbacksByRegistrationID[payload.registrationID] = callback
    }

    public override func connected(_ connection: VMPeerConnection) {
        super.connected(connection)
    }

    public override func disconnected(_ connection: VMPeerConnection) {
        super.disconnected(connection)

        DispatchQueue.main.async {
            self.invalidateObservations(for: connection.id)
        }
    }

    @MainActor
    private func handleRegistration(_ payload: VMNotificationRegistrationPayload, peer: VMPeerConnection) {
        logger.debug("Received registration request: \(payload)")

        do {
            let token = try observer.addObserver(id: payload.registrationID, for: payload.name, on: payload.type) { [weak self] in
                Task {
                    do {
                        self?.logger.debug("Local notification: \(payload)")

                        let notification = VMNotificationOccurredPayload(
                            registrationID: payload.registrationID,
                            type: payload.type,
                            name: payload.name
                        )

                        try await peer.send(notification)
                    } catch {
                        self?.logger.error("Error sending notification payload. \(error, privacy: .public)")
                    }
                }
            }

            keysByPeerID[peer.id, default: []].append(token)
        } catch {
            logger.error("Registration failed for \(payload). \(error, privacy: .public)")
        }
    }

    @MainActor
    private func invalidateObservations(for peerID: VMPeerConnection.ID) {
        guard let tokens = keysByPeerID[peerID], !tokens.isEmpty else { return }

        for token in tokens {
            observer.removeObserver(token)
        }

        keysByPeerID[peerID] = nil

        logger.debug("Invalidated \(tokens.count, privacy: .public) observations for \(peerID.shortID)")
    }

    @MainActor
    private func handleNotification(_ payload: VMNotificationOccurredPayload, peer: VMPeerConnection) {
        logger.debug("Remote notification occurred: \(payload)")

        guard let callback = callbacksByRegistrationID[payload.registrationID] else {
            logger.warning("We don't have a local registration for \(payload)")
            return
        }

        callback(payload.name)
    }
}
