import Foundation
import BuddyKit
import OSLog

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "VBSettings+CatalogDownload")

public extension VBSettings {
    private static let fallbackURL = FileManager.default.temporaryDirectory

    var downloadsDirectoryURL: URL {
        do {
            let baseURL = libraryURL.appendingPathComponent("_Downloads")

            if !FileManager.default.fileExists(atPath: baseURL.path) {
                logger.debug("Creating downloads directory at \(baseURL.path)")

                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            }

            return baseURL
        } catch {
            logger.fault("Error getting downloads base URL - \(error, privacy: .public)")

            return Self.fallbackURL
        }
    }

    func existingLocalURL(for remoteURL: URL) -> URL? {
        let downloadedFileURL = downloadsDirectoryURL.appendingPathComponent(remoteURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: downloadedFileURL.path) {
            return downloadedFileURL
        } else {
            return nil
        }
    }
}

extension VBSettings: CatalogDownloadsProvider {
    public func catalogDownloads() -> CatalogDownloads {
        do {
            var filesByName = [String : URL]()

            let files = try FilePath(downloadsDirectoryURL).children()

            for file in files {
                filesByName[file.lastComponent] = file.url
            }

            return CatalogDownloads(localFileURLByFileName: filesByName)
        } catch {
            logger.fault("Error enumerating downloads directory - \(error, privacy: .public)")
            return CatalogDownloads()
        }
    }
}
