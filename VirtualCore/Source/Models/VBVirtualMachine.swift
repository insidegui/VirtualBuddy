import Foundation
import UniformTypeIdentifiers
import Combine

public typealias VoidSubject = PassthroughSubject<(), Never>
public typealias BoolSubject = PassthroughSubject<Bool, Never>

public struct VBVirtualMachine: Identifiable {

    public enum DuplicationMethod: Int, Identifiable, CaseIterable {
        public var id: RawValue { rawValue }

        case changeID
        case clone
    }

    public struct Metadata: Codable {
        public static let currentVersion = 1
        public var version = Self.currentVersion
        public var installFinished: Bool = false
        public var firstBootDate: Date? = nil
        public var lastBootDate: Date? = nil
    }

    public var id: String { bundleURL.absoluteString }
    public let bundleURL: URL
    public var name: String { bundleURL.deletingPathExtension().lastPathComponent }

    private var _configuration: VBMacConfiguration?
    private var _metadata: Metadata?
    
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

    public private(set) var didInvalidateThumbnail = VoidSubject()
    
}

public extension VBVirtualMachine {
    static let bundleExtension = "vbvm"
    static let screenshotFileName = "Screenshot.tiff"
    static let thumbnailFileName = "Thumbnail.jpg"
}

extension VBVirtualMachine {

    static let metadataFilename = "Metadata.plist"
    static let configurationFilename = "Config.plist"
    
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

}

public extension UTType {
    static let virtualBuddyVM = UTType(exportedAs: "codes.rambo.VirtualBuddy.VM", conformingTo: .bundle)
}

public extension VBVirtualMachine {
    
    init(bundleURL: URL) throws {
        if !FileManager.default.fileExists(atPath: bundleURL.path) {
            #if DEBUG
            guard !ProcessInfo.isSwiftUIPreview else {
                fatalError("Missing SwiftUI preview VM at \(bundleURL.path)")
            }
            #endif
            
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        }
        
        self.bundleURL = bundleURL
        var (metadata, config) = try loadMetadata()

        /// Migration from previous versions that didn't have a configuration file
        /// describing the storage devices.
        config.hardware.addMissingBootDeviceIfNeeded()
        
        self.configuration = config

        if let metadata {
            self.metadata = metadata
        } else {
            /// Migration from previous versions that didn't have a metadata file.
            self.metadata = Metadata(installFinished: true, firstBootDate: .now, lastBootDate: .now)
        }

        try saveMetadata()
    }

    func saveMetadata() throws {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return }
        #endif
        
        let configData = try PropertyListEncoder().encode(configuration)
        try write(configData, forMetadataFileNamed: Self.configurationFilename)

        let metaData = try PropertyListEncoder().encode(metadata)
        try write(metaData, forMetadataFileNamed: Self.metadataFilename)
    }

    func loadMetadata() throws -> (Metadata?, VBMacConfiguration) {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return (nil, .default) }
        #endif

        let metadata: Metadata?
        let config: VBMacConfiguration

        if let data = metadataContents(Self.configurationFilename) {
            config = try PropertyListDecoder().decode(VBMacConfiguration.self, from: data)
        } else {
            config = .default
        }

        if let data = metadataContents(Self.metadataFilename) {
            metadata = try PropertyListDecoder().decode(Metadata.self, from: data)
        } else {
            metadata = nil
        }

        return (metadata, config)
    }

    mutating func reloadMetadata() {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return }
        #endif
        
        guard let (metadata, config) = try? loadMetadata() else {
            assertionFailure("Failed to reload metadata")
            return
        }

        self.metadata = metadata ?? .init()
        self.configuration = config
    }
    
}
