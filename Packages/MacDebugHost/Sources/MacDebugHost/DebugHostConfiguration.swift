import Foundation

/// Locations owned by the adopting app. Use a short per-user socket directory
/// because Darwin limits the length of Unix-domain socket addresses.
public struct DebugHostConfiguration: Sendable {
    public let applicationURL: URL
    public let helperURL: URL
    public let runtimeDirectory: URL

    public init(applicationURL: URL, helperURL: URL, runtimeDirectory: URL) {
        self.applicationURL = applicationURL
        self.helperURL = helperURL
        self.runtimeDirectory = runtimeDirectory
    }

    func endpoint(pid: pid_t) -> URL {
        runtimeDirectory.appendingPathComponent("host-\(pid).sock")
    }
}
