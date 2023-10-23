import Cocoa

/// Describes a user's decision about a client opening deep links in the app.
public enum DeepLinkClientAuthorization: Int, Codable, CustomStringConvertible {
    /// The user has not granted/rejected the client yet.
    /// Also used as a fallback when something goes wrong in the process of
    /// authenticating a previously authorized/denied client.
    case undetermined
    /// The user has granted authorization to the client.
    case authorized
    /// The user has denied authorization for the client.
    case denied
}

public extension DeepLinkClientAuthorization {
    var description: String {
        switch self {
        case .undetermined:
            return "undetermined"
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        }
    }
}

/// Implemented by types that can provide persistence for user's decision regarding the opening of deep links from other apps.
/// See ``MemoryDeepLinkAuthStore`` and ``KeychainDeepLinkAuthStore``.
public protocol DeepLinkAuthStore {
    func authorization(for client: DeepLinkClient) async -> DeepLinkClientAuthorization
    func setAuthorization(_ authorization: DeepLinkClientAuthorization, for client: DeepLinkClient) async throws
}
