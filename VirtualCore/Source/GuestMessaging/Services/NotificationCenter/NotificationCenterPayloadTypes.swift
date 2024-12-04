import Foundation
import AppKit
import MessageRouter

/// Host or guest sends to peer in order to register for notifications that happen on the other side.
struct VMNotificationRegistrationPayload: RoutableMessagePayload, Hashable, CustomStringConvertible {
    var registrationID: UUID = UUID()
    var type: NotificationCenterType
    var name: String
}

/// Sent when a registered notification occurs on the system.
struct VMNotificationOccurredPayload: RoutableMessagePayload, Hashable, CustomStringConvertible {
    var registrationID: UUID = UUID()
    var type: NotificationCenterType
    var name: String
    var timestamp: TimeInterval = Date.now.timeIntervalSinceReferenceDate
}

extension VMNotificationRegistrationPayload {
    var description: String { "\(registrationID.shortID)<\(type.rawValue):\(name)>" }
}

extension VMNotificationOccurredPayload {
    var description: String { "\(registrationID.shortID)<\(type.rawValue):\(name)>" }
}
