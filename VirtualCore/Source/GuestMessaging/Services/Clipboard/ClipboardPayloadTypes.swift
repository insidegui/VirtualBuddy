import Foundation
import AppKit
import MessageRouter

struct VMClipboardData: RoutableMessagePayload, Hashable {
    var type: NSPasteboard.PasteboardType.RawValue
    var value: Data
}

struct VMClipboardPayload: RoutableMessagePayload, Hashable {
    var timestamp: Date
    var data: [VMClipboardData]

    static let propagateBetweenGuests = true
}

extension VMClipboardData: CustomStringConvertible {
    var description: String { "\(type) (\(value.count) bytes)" }
}

extension VMClipboardPayload: CustomStringConvertible {
    var description: String {
        "\(timestamp.timeIntervalSinceReferenceDate): \(data.map(\.description).joined(separator: ","))"
    }
}
