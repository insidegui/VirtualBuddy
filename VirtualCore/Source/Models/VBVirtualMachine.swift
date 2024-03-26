import Foundation
import UniformTypeIdentifiers
import Combine

public typealias VoidSubject = PassthroughSubject<(), Never>
public typealias BoolSubject = PassthroughSubject<Bool, Never>

public struct VBVirtualMachine: Identifiable {

    public struct Metadata: Codable {
        public static let currentVersion = 1
        public var version = Self.currentVersion
        public var installFinished: Bool = false
        public var firstBootDate: Date? = nil
        public var lastBootDate: Date? = nil
        public var installImageURL: URL? = nil
        @DecodableDefault.EmptyPlaceholder
        public var uuid = UUID()
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

    public private(set) var didInvalidateThumbnail = VoidSubject()
    
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

    func diskImageURL(for device: VBStorageDevice) -> URL {
        switch device.backing {
        case .managedImage(let image):
            return diskImageURL(for: image)
        case .customImage(let customURL):
            return customURL
        }
    }
    
    func diskImageURL(for image: VBManagedDiskImage) -> URL {
        bundleURL
            .appendingPathComponent(image.filename)
            .appendingPathExtension(image.format.fileExtension)
    }

    public var bootDevice: VBStorageDevice {
        get throws {
            guard let device = configuration.hardware.storageDevices.first(where: { $0.isBootVolume }) else {
                throw Failure("The virtual machine doesn't have a storage device to boot from.")
            }
            
            return device
        }
    }

    var bootDiskImage: VBManagedDiskImage {
        get throws {
            let device = try bootDevice

            guard case .managedImage(let image) = device.backing else {
                throw Failure("The boot device must use a disk image managed by VirtualBuddy")
            }
            
            return image
        }
    }

    var auxiliaryStorageURL: URL {
        bundleURL.appendingPathComponent("AuxiliaryStorage")
    }
    
    var machineIdentifierURL: URL {
        bundleURL.appendingPathComponent("MachineIdentifier")
    }
    
    var hardwareModelURL: URL {
        bundleURL.appendingPathComponent("HardwareModel")
    }

    var metadataDirectoryURL: URL { Self.metadataDirectoryURL(for: bundleURL) }

    static func metadataDirectoryURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(".vbdata")
    }

    public var needsInstall: Bool {
        guard configuration.systemType == .mac else { return false }
        return !metadata.installFinished || !FileManager.default.fileExists(atPath: hardwareModelURL.path)
    }

}

public extension UTType {
    static let virtualBuddyVM = UTType(exportedAs: "codes.rambo.VirtualBuddy.VM", conformingTo: .bundle)
}

public extension VBVirtualMachine {
    
    init(bundleURL: URL, isNewInstall: Bool = false) throws {
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
        
        self.configuration = config

        if let metadata {
            self.metadata = metadata
        } else {
            /// Migration from previous versions that didn't have a metadata file.
            self.metadata = Metadata(installFinished: !isNewInstall, firstBootDate: .now, lastBootDate: .now)
        }

        self.installRestoreData = installRestore

        try saveMetadata()
    }

    @available(macOS 13, *)
    init(creatingAtURL bundleURL: URL, linuxInstallerURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: bundleURL.path) else { fatalError() }
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        self.bundleURL = bundleURL
        self.configuration = .init(systemType: .linux)
        self.metadata = Metadata(installFinished: false, firstBootDate: .now, lastBootDate: .now, installImageURL: linuxInstallerURL)
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

        if let installRestoreData {
            try write(installRestoreData, forMetadataFileNamed: Self.installRestoreFilename)
        } else {
            try? deleteMetadataFile(named: Self.installRestoreFilename)
        }
    }

    func loadMetadata() throws -> (Metadata?, VBMacConfiguration, Data?) {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return (nil, .default, nil) }
        #endif

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
