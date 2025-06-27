import Foundation
import BuddyFoundation
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "VMImporterRegistry")

/// Keeps track of available importers and helps find the importer to use for a given external VM bundle.
@MainActor
public struct VMImporterRegistry {
    public static let `default` = VMImporterRegistry()

    private let importers: [VMImporter] = [
        UTMImporter()
    ]

    public var supportedFileTypes: Set<UTType> {
        Set(importers.map(\.fileType))
    }

    /// Returns the importer that can handle the file at the specified path.
    public func importer(for filePath: FilePath) -> VMImporter? {
        logger.debug("Look up importer for \(filePath)")

        guard let uti = filePath.contentType else {
            logger.error("Couldn't determine UTI for importing \(filePath)")
            return nil
        }

        guard let importer = importers.first(where: { uti.conforms(to: $0.fileType) }) else {
            logger.notice("No importer found for type \(uti.identifier, privacy: .public)")
            return nil
        }

        logger.notice("Matched importer \(importer.appName.quoted, privacy: .public) for type \(uti.identifier, privacy: .public)")

        return importer
    }
}
