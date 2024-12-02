import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

struct VMPingPayload: RespondableMessagePayload {
    var id = UUID().uuidString
    var timestamp = Date.now.timeIntervalSinceReferenceDate
}

public struct VMPongPayload: RespondableMessagePayload {
    public internal(set) var id = UUID().uuidString
    public internal(set) var timestamp = Date.now.timeIntervalSinceReferenceDate
}
