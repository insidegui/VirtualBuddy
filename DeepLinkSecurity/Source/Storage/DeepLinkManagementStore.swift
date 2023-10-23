import Foundation

/// Implemented by types that can provide persistence for a list of authorized/denied deep link clients,
/// so that a UI can be assembled showing the user their previous decisions and allowing users to change their mind.
public protocol DeepLinkManagementStore {
    /// Returns all deep link client descriptors previously added using ``insert(_:)``.
    nonisolated func clientDescriptors() -> AsyncStream<[DeepLinkClientDescriptor]>

    /// Whether the store currently has a descriptor with the specified identifier.
    func hasDescriptor(with id: DeepLinkClientDescriptor.ID) async -> Bool

    /// Upserts a client descriptor.
    func insert(_ descriptor: DeepLinkClientDescriptor) async throws

    /// Deletes an existing descriptor.
    func delete(_ descriptor: DeepLinkClientDescriptor) async throws
}
