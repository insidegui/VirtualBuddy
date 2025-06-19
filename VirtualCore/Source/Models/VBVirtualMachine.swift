import Foundation
import UniformTypeIdentifiers
import Combine

public typealias VoidSubject = PassthroughSubject<(), Never>
public typealias BoolSubject = PassthroughSubject<Bool, Never>

public struct VBVirtualMachine: Identifiable, VBStorageDeviceContainer {

    public struct Metadata: Hashable, Codable {
        public static let currentVersion = 1
        @DecodableDefault.EmptyPlaceholder
        public var uuid = UUID()
        public var version = Self.currentVersion
        public var installFinished: Bool = false
        public var firstBootDate: Date? = nil
        public var lastBootDate: Date? = nil
        @DecodableDefault.EmptyPlaceholder
        public var backgroundHash: BlurHashToken = .virtualBuddyBackground
        /// If this VM was imported from some other app, contains the name of the ``VMImporter`` that was used.
        public var importedFromAppName: String? = nil

        /// The original remote URL that was specified for downloading the restore image (if downloaded from a remote source).
        public private(set) var remoteInstallImageURL: URL? = nil

        /// The original local file URL that was specified (or set after a successful download from ``remoteInstallImageURL``).
        public private(set) var installImageURL: URL? = nil

        /**
         Usage of the same property for both local and remote restore image URLs has been the source of recurring bugs in the past.
         Example: https://github.com/insidegui/VirtualBuddy/pull/395
         
         To keep this struct backwards-compatible and still have better safeguards against regressions, ``remoteInstallImageURL`` and ``installImageURL``
         are only settable by the struct itself. To update the metadata, clients must use this method, which will automatically set the correct property by inspecting the URL.
         */
        public mutating func updateInstallImageURL(_ url: URL) {
            if url.isFileURL {
                installImageURL = url
            } else {
                remoteInstallImageURL = url
            }
        }

        /// If Linux VM is using fallback VirtualBuddy orange background hash, updates it to use the Linux-specific one.
        fileprivate mutating func setLinuxBackgroundHashIfNeeded() {
            guard backgroundHash == .virtualBuddyBackground else { return }
            backgroundHash = .virtualBuddyBackgroundLinux
        }
    }

    public var id: String { bundleURL.absoluteString }
    public internal(set) var bundleURL: URL
    public var name: String { bundleURL.deletingPathExtension().lastPathComponent }

    public internal(set) var uuid: UUID {
        get { metadata.uuid }
        set { metadata.uuid = newValue }
    }

    private var _configuration: VBMacConfiguration?
    private var _metadata: Metadata?
    private var _installRestoreData: Data?

    public var configuration: VBMacConfiguration {
        /// Masking private `_configuration` since it's initialized dynamically from a file.
        get { _configuration ?? .default }
        set { _configuration = newValue }
    }

    public var metadata: Metadata {
        /// Masking private `_metadata` since it's initialized dynamically from a file.
        get { _metadata ?? .init() }
        set { _metadata = newValue }
    }

    public var installRestoreData: Data? {
        /// Masking private `_installRestoreData` since it's initialized dynamically from a file.
        get { _installRestoreData }
        set { _installRestoreData = newValue }
    }
    
}

public extension VBVirtualMachine {
    static let bundleExtension = "vbvm"
    static let screenshotFileName = "Screenshot.heic"
    static let thumbnailFileName = "Thumbnail.heic"
    
    /// Only used for migrations.
    static let _legacyScreenshotFileName = "Screenshot.tiff"
    /// Only used for migrations.
    static let _legacyThumbnailFileName = "Thumbnail.jpg"
}

extension VBVirtualMachine {

    static let metadataFilename = "Metadata.plist"
    static let configurationFilename = "Config.plist"
    static let installRestoreFilename = "Install.plist"

    public var storageDevices: [VBStorageDevice] { configuration.hardware.storageDevices }

    var auxiliaryStorageURL: URL {
        bundleURL.appendingPathComponent("AuxiliaryStorage")
    }
    
    var machineIdentifierURL: URL {
        bundleURL.appendingPathComponent("MachineIdentifier")
    }
    
    var hardwareModelURL: URL {
        bundleURL.appendingPathComponent("HardwareModel")
    }

    public var metadataDirectoryURL: URL { Self.metadataDirectoryURL(for: bundleURL) }

    static let metadataDirectoryName = ".vbdata"

    static func metadataDirectoryURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(metadataDirectoryName)
    }

    public var needsInstall: Bool {
        guard configuration.systemType == .mac else { return false }
        return !metadata.installFinished || !FileManager.default.fileExists(atPath: hardwareModelURL.path)
    }

    /// Conforming to ``VBStorageDeviceContainer``, which defaults this to `false`.
    /// When restoring from a saved state, disk image creation is not allowed, but when bootstrapping
    /// a virtual machine, disk image creation is allowed.
    public var allowDiskImageCreation: Bool { true }

}

public extension UTType {
    static let virtualBuddyVM = UTType(exportedAs: "codes.rambo.VirtualBuddy.VM", conformingTo: .bundle)
}

public extension VBVirtualMachine {

    struct BundleDirectoryMissingError: Error { }

    init(bundleURL: URL, isNewInstall: Bool = false, createIfNeeded: Bool = true) throws {
        /// If we're not allowed to create the bundle and its metadata directory doesn't exist, throw a specific error type that's caught in ``VMLibraryController``.
        /// This is to prevent the app from creating a dummy VM bundle after a VM is deleted from the library.
        if !createIfNeeded {
            let metaDirectory = bundleURL.appending(path: Self.metadataDirectoryName, directoryHint: .isDirectory)
            guard metaDirectory.isReadableDirectory else {
                throw BundleDirectoryMissingError()
            }
        }

        if !FileManager.default.fileExists(atPath: bundleURL.path) {
            #if DEBUG
            guard !ProcessInfo.isSwiftUIPreview else {
                fatalError("Missing SwiftUI preview VM at \(bundleURL.path)")
            }
            #endif
            
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        }

        self.bundleURL = bundleURL
        var (metadata, config, installRestore) = try loadMetadata()

        /// Migration from previous versions that didn't have a configuration file
        /// describing the storage devices.
        config.hardware.addMissingBootDeviceIfNeeded()

        /// Migration from previous versions that didn't have dedicated fallback artwork for Linux.
        if config.systemType == .linux {
            metadata?.setLinuxBackgroundHashIfNeeded()
        }

        self.configuration = config

        if let metadata {
            self.metadata = metadata
        } else {
            /// Migration from previous versions that didn't have a metadata file.
            self.metadata = Metadata(installFinished: !isNewInstall, firstBootDate: .now, lastBootDate: .now)
        }

        self.installRestoreData = installRestore
    }

    @available(macOS 13, *)
    init(creatingLinuxMachineAt bundleURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: bundleURL.path) else { fatalError() }
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        self.bundleURL = bundleURL
        self.configuration = .init(systemType: .linux)

        self.metadata = Metadata(installFinished: false, firstBootDate: .now, lastBootDate: .now)
        metadata.setLinuxBackgroundHashIfNeeded()

        try saveMetadata()
    }

    func saveMetadata() throws {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return }
        #endif
        
        let configData = try PropertyListEncoder.virtualBuddy.encode(configuration)
        try write(configData, forMetadataFileNamed: Self.configurationFilename)

        let metaData = try PropertyListEncoder.virtualBuddy.encode(metadata)
        try write(metaData, forMetadataFileNamed: Self.metadataFilename)

        try saveInstallData()
    }

    func saveInstallData() throws {
        if let installRestoreData {
            try write(installRestoreData, forMetadataFileNamed: Self.installRestoreFilename)
        } else {
            try? deleteMetadataFile(named: Self.installRestoreFilename)
        }
    }

    func loadMetadata() throws -> (Metadata?, VBMacConfiguration, Data?) {
        let metadata: Metadata?
        let config: VBMacConfiguration
        let installRestore: Data?

        if let data = metadataContents(Self.configurationFilename) {
            config = try PropertyListDecoder.virtualBuddy.decode(VBMacConfiguration.self, from: data)
        } else {
            /// Linux guests don't go through this code path, so it should be safe to assume Mac here (famous last words).
            config = .default.guestType(.mac)
        }

        if let data = metadataContents(Self.metadataFilename) {
            metadata = try PropertyListDecoder.virtualBuddy.decode(Metadata.self, from: data)
        } else {
            metadata = nil
        }

        if let data = metadataContents(Self.installRestoreFilename) {
            installRestore = data
        } else {
            installRestore = nil
        }

        return (metadata, config, installRestore)
    }

    mutating func reloadMetadata() {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return }
        #endif
        
        guard let (metadata, config, installRestore) = try? loadMetadata() else {
            assertionFailure("Failed to reload metadata")
            return
        }

        self.metadata = metadata ?? .init()
        self.configuration = config
        self.installRestoreData = installRestore
    }

}

extension URL {
    var creationDate: Date {
        get { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast }
        set {
            var values = URLResourceValues()
            values.creationDate = newValue
            try? setResourceValues(values)
        }
    }
}

public extension PropertyListEncoder {
    static let virtualBuddy = PropertyListEncoder()
}

public extension PropertyListDecoder {
    static let virtualBuddy = PropertyListDecoder()
}

extension UUID: ProvidesEmptyPlaceholder {
    public static var empty: UUID { UUID() }
}
