import Foundation
import FragmentZip

extension BuildManifest {
    init(remoteIPSWURL url: URL, build: String) async throws {
        let manifestFileName = "BuildManifest-\(build).plist"

        let cachedManifestURL = try URL.vctoolBuildManifestCache.appending(path: manifestFileName)

        let manifestURL: URL

        if cachedManifestURL.exists {
            fputs("Using cached build manifest for \(build)\n", stderr)

            manifestURL = cachedManifestURL
        } else {
            fputs("Retrieving build manifest for \(build)\n", stderr)

            let ipsw = FragmentZip(url: url)
            let downloadedManifestURL = try await ipsw.download(filePath: "BuildManifest.plist", as: manifestFileName)

            do {
                try FileManager.default.copyItem(at: downloadedManifestURL, to: cachedManifestURL)
            } catch {
                fputs("WARN: Failed to cache build manifest: \(error)\n", stderr)
            }

            manifestURL = downloadedManifestURL
        }

        try self.init(contentsOf: manifestURL)
    }
}

extension URL {
    static var vctoolBuildManifestCache: URL {
        get throws {
            try URL.vctoolCache
                .appending(path: "BuildManifests", directoryHint: .isDirectory)
                .ensureExistingDirectory(createIfNeeded: true)
        }
    }
}
