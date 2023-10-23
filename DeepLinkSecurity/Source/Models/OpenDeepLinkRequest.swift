import Foundation

/// Represents a client's request for opening a deep link in the app.
public struct OpenDeepLinkRequest {
    /// The URL for the deep link the client is trying to open.
    public var url: URL
    /// The client model used for authentication.
    public var client: DeepLinkClientDescriptor

    public init(url: URL, client: DeepLinkClientDescriptor) {
        self.url = url
        self.client = client
    }
}
