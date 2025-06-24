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
}

extension VBSettings: CatalogDownloadsProvider {
    public func localFileURL(for restoreImage: RestoreImage) -> URL? {
        do {
            let files = try FilePath(downloadsDirectoryURL).children().map(\.url.vb_restoreImageStub)

            guard let stub = files.vb_elementMatchingDownloadableCatalogContent(at: restoreImage.url) else { return nil }

            logger.debug("Found download matching \(restoreImage.name.quoted) - \(stub)")

            /// Take this opportunity to set the extended attribute if it hasn't been set yet.
            stub.url.vb_addSoftwareCatalogExtendedAttributeIfNeeded(for: restoreImage)

            return stub.url
        } catch {
            logger.fault("Error enumerating downloads directory - \(error, privacy: .public)")

            return nil
        }
    }
}

extension URL {
    private static let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "URL+SoftwareCatalogAttribute")

    func vb_addSoftwareCatalogExtendedAttributeIfNeeded(for restoreImage: RestoreImage) {
        guard vb_softwareCatalogData == nil else { return }

        Self.logger.debug("Adding software catalog extended attribute for \(restoreImage.build) to \(lastPathComponent.quoted)")

        vb_softwareCatalogData = VirtualBuddyCatalogData(
            build: restoreImage.build,
            filename: restoreImage.url.lastPathComponent
        )
    }
}
