import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

enum VMSystemAppearance: Int32, Codable, CustomStringConvertible, Sendable {
    case light
    case dark

    var description: String {
        switch self {
        case .light: "light"
        case .dark: "dark"
        }
    }
}

/// Sent from host to guest when host system appearance changes.
struct VMAppearanceChangePayload: RoutableMessagePayload {
    var appearance: VMSystemAppearance
}

/// Sent from guest to host when guest wants to perform an initial sync of the host's system appearance.
struct VMHostAppearanceRequest: RespondableMessagePayload {
    var id: String = UUID().uuidString
}

/// Sent from host to guest in response to `VMRequestHostAppearancePayload`.
struct VMHostAppearanceResponse: RespondableMessagePayload {
    var id: String
    var appearance: VMSystemAppearance
}
