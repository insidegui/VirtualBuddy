import Foundation
import MacDebugProtocol

/// Locations owned by the adopting app. Use a short per-user socket directory
/// because Darwin limits the length of Unix-domain socket addresses.
public struct DebugHostConfiguration: Sendable {
    public let applicationURL: URL
    public let helperURL: URL
    public let runtimeDirectory: URL
    /// A per-user directory that stays in place when the app is updated, moved or renamed.
    /// Generated schemes live in the developer's projects, where the app cannot find them
    /// again, so they refer to the links in this directory and never to the app bundle.
    public let linksDirectory: URL

    public init(applicationURL: URL, helperURL: URL, runtimeDirectory: URL, linksDirectory: URL) {
        self.applicationURL = applicationURL
        self.helperURL = helperURL
        self.runtimeDirectory = runtimeDirectory
        self.linksDirectory = linksDirectory
    }

    func endpoint(pid: pid_t) -> URL {
        runtimeDirectory.appendingPathComponent("host-\(pid).sock")
    }

    // Existing schemes contain these two paths. Keep the names when changing anything else.
    var helperLink: URL { linksDirectory.appendingPathComponent("helper") }
    var moduleLink: URL { linksDirectory.appendingPathComponent("mac_debug.py") }

    /// Points the links at this copy of the app. Call when the app starts accepting runs
    /// and before generating a scheme, so schemes follow the app wherever it is installed.
    public func refreshLinks() throws {
        guard let module = Bundle.module.url(forResource: "mac_debug", withExtension: "py") else {
            throw MacDebugError("Could not find the packaged LLDB module.")
        }
        try DebugTools.directory(linksDirectory)
        for (link, target) in [(helperLink, helperURL), (moduleLink, module)] {
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != target.path else { continue }
            // Renaming over the old link leaves no moment when a Run action finds it missing.
            let replacement = linksDirectory.appendingPathComponent("." + UUID().uuidString)
            try FileManager.default.createSymbolicLink(atPath: replacement.path, withDestinationPath: target.path)
            guard rename(replacement.path, link.path) == 0 else {
                let failure = POSIXError(.init(rawValue: errno) ?? .EIO)
                try? FileManager.default.removeItem(at: replacement)
                throw failure
            }
        }
    }
}
