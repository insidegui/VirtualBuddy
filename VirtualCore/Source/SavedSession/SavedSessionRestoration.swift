import Foundation

/// Everything that makes a restored virtual machine different from a regular one.
///
/// `@unchecked Sendable` because the configuration is a plain value that is never mutated after it is captured.
struct SavedSessionRestoration: @unchecked Sendable {
    /// The configuration that was used to construct the virtual machine when its session was saved.
    var configuration: VBMacConfiguration
    /// The guest additions image that was attached when the session was saved, if any.
    var guestAdditionsMediaURL: URL?
}
