import Foundation
import VMBridge

@MainActor
final class DesktopPictureGuestService: GuestService {
    private let desktopPicture: () async throws -> GuestDesktopPicture?
    var onDesktopPicture: ((GuestDesktopPicture) -> Void)?

    init(context: GuestServiceContext, desktopPicture: @escaping () async throws -> GuestDesktopPicture?) {
        self.desktopPicture = desktopPicture
        super.init(context: context)
    }
    override func subscriptions() -> [Subscription] {
        let pictures = connection.messages(of: DesktopPictureUpdate.self)
        return [{ for await picture in pictures { await self.receivePicture(picture) } }]
    }
    override func activate(notifications: Set<String>) {
        guard !isHost, let token = session else { return }
        schedule { try await self.sendDesktopPicture(token: token) }
    }

    func sendDesktopPicture() async throws {
        guard !isHost, let token = session else { throw GuestSessionError.disconnected }
        try await sendDesktopPicture(token: token)
    }

    private func sendDesktopPicture(token: UUID) async throws {
        guard let picture = try await desktopPicture() else {
            logger.debug("No desktop picture is available")
            return
        }
        try requireSession(token)
        logger.debug("Sending desktop picture (\(picture.content.count) bytes)")
        try await connection.send(DesktopPictureUpdate(session: token, type: picture.type, content: picture.content))
    }

    private func receivePicture(_ picture: DesktopPictureUpdate) {
        guard isHost, session == picture.session, !Task.isCancelled else { return }
        logger.debug("Received desktop picture (\(picture.content.count) bytes)")
        onDesktopPicture?(.init(type: picture.type, content: picture.content))
    }

}
