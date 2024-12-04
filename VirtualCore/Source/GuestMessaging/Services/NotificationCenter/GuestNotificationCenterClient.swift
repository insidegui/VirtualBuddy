import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

public class NotificationCenterClient: GuestNotificationCenterService, GuestServiceClient, @unchecked Sendable {
    override var isGuest: Bool { false }
}
