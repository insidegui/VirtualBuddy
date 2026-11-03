import Foundation
import VMBridge

@MainActor
final class NotificationsGuestService: GuestService {
    private let observe: (Set<String>, @escaping @MainActor (String) -> Void) throws -> (() -> Void)
    private var removeNotifications: (() -> Void)?
    var onNotification: ((String) -> Void)?
    private static let notificationNames: Set<String> = ["com.apple.shieldWindowRaised", "com.apple.shieldWindowLowered"]
    override var requestedNotifications: Set<String> { Self.notificationNames }

    init(context: GuestServiceContext, observe: @escaping (Set<String>, @escaping @MainActor (String) -> Void) throws -> (() -> Void)) {
        self.observe = observe
        super.init(context: context)
    }
    override func subscriptions() -> [Subscription] {
        let notifications = connection.messages(of: GuestNotification.self)
        return [{ for await notification in notifications { await self.receiveNotification(notification) } }]
    }
    override func activate(notifications: Set<String>) throws {
        guard !isHost, let token = session else { return }
        removeNotifications = try observe(notifications.intersection(Self.notificationNames)) { [weak self] name in
            guard let self, self.session == token else { return }
            self.schedule { try self.requireSession(token); try await self.connection.send(GuestNotification(session: token, name: name)) }
        }
    }
    override func invalidate() {
        super.invalidate()
        removeNotifications?()
        removeNotifications = nil
    }

    private func receiveNotification(_ notification: GuestNotification) {
        guard isHost, session == notification.session, Self.notificationNames.contains(notification.name), !Task.isCancelled else { return }
        onNotification?(notification.name)
    }
}
