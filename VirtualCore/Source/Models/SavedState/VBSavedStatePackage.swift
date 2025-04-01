import Foundation
import UniformTypeIdentifiers
import OSLog

public extension UTType {
    static let virtualBuddySavedState = UTType(
        exportedAs: "codes.rambo.VirtualBuddy.SavedState",
        conformingTo: .bundle
    )
}

/// Represents a `vbst` file on disk, encapsulating all operations related to saved state packages.
public final class VBSavedStatePackage: Identifiable, Hashable, Codable {
    public var id: UUID { metadata.id }

    static let dataFilename = "State.vzvmsave"
    static let infoFilename = "Info.plist"
    static let screenshotFilename = "Screenshot.heic"
    static let thumbnailFilename = "Thumbnail.heic"
    static let fileExtension = "vbst"

    public let url: URL
    public let dataFileURL: URL
    public let infoFileURL: URL
    public let screenshotFileURL: URL
    public let thumbnailFileURL: URL
    private let manager: FileManager
    private let logger: Logger
    public var metadata: VBSavedStateMetadata {
        didSet { saveMetadata(oldValue) }
    }

    /// Creates a new package on disk for the given virtual machine, initializing the saved state package accordingly.
    public convenience init(creatingPackageInDirectoryAt baseURL: URL, model: VBVirtualMachine, snapshotName: String) throws {
        let url = baseURL.appendingPathComponent(snapshotName, conformingTo: .virtualBuddySavedState)
        let createdURL = try url.creatingDirectoryIfNeeded()

        try self.init(url: createdURL, metadata: VBSavedStateMetadata(model: model))

        save()
    }

    /// Initializes a saved state package from an existing package on disk.
    public convenience init(url: URL) throws {
        try self.init(url: url, metadata: nil)
    }

    private init(url: URL, metadata: VBSavedStateMetadata?) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure("Saved state package doesn't exist at \(url.path)")
        }
        let infoURL = url.appending(path: Self.infoFilename)
        self.logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "VBSavedStatePackage(\(url.deletingPathExtension().lastPathComponent))")
        self.manager = FileManager()
        self.url = url
        self.dataFileURL = url.appending(path: Self.dataFilename)
        self.infoFileURL = infoURL
        self.screenshotFileURL = url.appending(path: Self.screenshotFilename)
        self.thumbnailFileURL = url.appending(path: Self.thumbnailFilename)

        if FileManager.default.fileExists(atPath: infoURL.path) {
            let data = try Data(contentsOf: infoURL)
            self.metadata = try PropertyListDecoder.virtualBuddy.decode(VBSavedStateMetadata.self, from: data)
        } else {
            guard let inputMetadata = metadata else {
                throw Failure("Initializing VBSavedStatePackage with new package requires metadata to be provided")
            }
            self.metadata = inputMetadata
        }
    }

    public var thumbnail: NSImage? { NSImage(contentsOf: thumbnailFileURL) }

    public var screenshot: NSImage? {
        get { NSImage(contentsOf: screenshotFileURL) }
        set {
            guard let newValue else {
                try? manager.removeItem(at: screenshotFileURL)
                try? manager.removeItem(at: thumbnailFileURL)
                return
            }

            do {
                try newValue.vb_encodeHEIC(to: screenshotFileURL)
                try newValue.vb_createThumbnail(at: thumbnailFileURL)
            } catch {
                logger.error("Error saving new screenshot/thumbnail: \(error, privacy: .public)")
            }
        }
    }

    public func save() {
        logger.debug(#function)
        
        saveMetadata(nil)
    }

    public func delete() throws {
        logger.debug(#function)

        try manager.removeItem(at: url)
    }

    private func saveMetadata(_ oldValue: VBSavedStateMetadata?) {
        guard metadata != oldValue else { return }

        do {
            let encoded = try PropertyListEncoder.virtualBuddy.encode(metadata)
            try encoded.write(to: infoFileURL)
        } catch {
            logger.error("Error saving updated info: \(error, privacy: .public)")

            assertionFailure("Error saving updated info: \(error)")
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(metadata)
    }

    public static func ==(lhs: VBSavedStatePackage, rhs: VBSavedStatePackage) -> Bool { lhs.metadata == rhs.metadata }
}

// MARK: - Validation

extension VBSavedStatePackage {
    func validate(for model: VBVirtualMachine) throws {
        if let stateHostECID = metadata.hostECID,
           let currentHostECID = ProcessInfo.processInfo.machineECID
        {
            guard stateHostECID == currentHostECID else {
                throw Failure("This saved state is not for the current host. Saved states are paired to the host machine and can't be restored on a different host.")
            }
        }

        guard metadata.vmUUID == model.metadata.uuid else {
            throw Failure("This saved state is not for this virtual machine. Saved states can only be restored on the virtual machine that saved the state.")
        }
    }
}

// MARK: - Codable Conformance

public extension VBSavedStatePackage {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url.path)
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let path = try container.decode(String.self)
        try self.init(url: URL(filePath: path))
    }
}
