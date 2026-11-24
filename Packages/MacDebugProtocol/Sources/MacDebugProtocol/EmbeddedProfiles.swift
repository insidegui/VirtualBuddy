import Foundation

public enum EmbeddedProfiles {
    /// Includes nested apps, extensions, system extensions and XPC services, even when
    /// a helper is packaged in a nonstandard location. Never follows directory symlinks.
    public static func find(in product: URL) throws -> [URL] {
        var readError: Error?
        let root = product.resolvingSymlinksInPath().standardizedFileURL
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                                         errorHandler: { _, error in readError = error; return false }) else {
            throw MacDebugError("Could not read \(product.lastPathComponent).")
        }
        var profiles: [URL] = []
        for case let file as URL in files where file.lastPathComponent == "embedded.provisionprofile" &&
            file.deletingLastPathComponent().lastPathComponent == "Contents" {
            let type = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard type.isSymbolicLink != true, type.isRegularFile == true else {
                throw MacDebugError("An embedded provisioning profile must be a regular file.")
            }
            profiles.append(file.standardizedFileURL)
        }
        if let readError { throw readError }
        return profiles.sorted { $0.path < $1.path }
    }
}
