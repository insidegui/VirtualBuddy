import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

struct VMPingPayload: RoutableMessagePayload {
    var id = UUID().uuidString
    var timestamp = Date.now.timeIntervalSinceReferenceDate
}

public struct VMPongPayload: RoutableMessagePayload {
    public internal(set) var id = UUID().uuidString
    public internal(set) var timestamp = Date.now.timeIntervalSinceReferenceDate
}
