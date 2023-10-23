import Foundation
import CryptoKit

/// Represents an app/process that's attempting to open a deep link in the app.
public struct DeepLinkClient: Identifiable {
    /// The client ID is a SHA256 hash of its designated CS requirement.
    public var id: String
    /// The bundle URL for the app or executable URL for the process.
    public var url: URL
    /// The designated code signing requirement for the client.
    /// This is hashed and used as a key to store the user's decision,
    /// and it's also used in order to verify that the client's code signature is valid.
    public var designatedRequirement: String

    public init(url: URL, designatedRequirement: String) {
        self.url = url
        self.designatedRequirement = designatedRequirement
        self.id = SHA256.hash(data: Data(designatedRequirement.utf8))
            .map { String(format: "%02X", $0) }
            .joined()
    }
}
