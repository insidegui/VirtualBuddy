import Cocoa

/// Describes metadata for a client that's previously requested deep link authorization.
/// See ``DeepLinkManagementStore``.
public struct DeepLinkClientDescriptor: Identifiable, Hashable, Codable {
    public struct Icon: Hashable, Codable {
        public var image: NSImage
    }

    /// Unique identifier for the client.
    public var id: String
    /// The client's main bundle or executable URL.
    public var url: URL
    /// The client's bundle identifier, if available.
    public var bundleIdentifier: String?
    /// A user-friendly name for the client.
    public var displayName: String
    /// Icon image representing the client app or executable.
    public var icon: Icon
    /// The current authorization state for the client.
    public var authorization: DeepLinkClientAuthorization
    /// Will be `false` if the descriptor's client could no longer be found on the filesystem.
    public var isValid: Bool
}
