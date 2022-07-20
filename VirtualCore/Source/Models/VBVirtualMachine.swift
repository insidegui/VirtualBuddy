import Foundation
import UniformTypeIdentifiers
import Combine

public typealias VoidSubject = PassthroughSubject<(), Never>

public struct VBVirtualMachine: Identifiable {

    public var id: String { bundleURL.absoluteString }
    public let bundleURL: URL
    public var name: String { bundleURL.deletingPathExtension().lastPathComponent }
    private var _configuration: VBMacConfiguration?
    
    public var configuration: VBMacConfiguration {
        /// Masking private `_configuration` to avoid making the public API optional
        /// without having to do any special `Codable` shenanigans.
        get { _configuration ?? .default }
        set { _configuration = newValue }
    }

    public private(set) var didInvalidateThumbnail = VoidSubject()
    
}

public extension VBVirtualMachine {
    static let bundleExtension = "vbvm"
    static let screenshotFileName = "Screenshot.tiff"
    static let thumbnailFileName = "Thumbnail.jpg"
}

extension VBVirtualMachine {

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
    
    var bootDevice: VBStorageDevice {
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
        var config = try loadConfiguration()
        
        config.hardware.addMissingBootDeviceIfNeeded()
        
        self.configuration = config

        try saveConfiguration()
    }

    func saveConfiguration() throws {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return }
        #endif
        
        let configData = try PropertyListEncoder().encode(configuration)
        try write(configData, forMetadataFileNamed: Self.configurationFilename)
    }

    func loadConfiguration() throws -> VBMacConfiguration {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return .default }
        #endif
        
        if let data = metadataContents(Self.configurationFilename) {
            return try PropertyListDecoder().decode(VBMacConfiguration.self, from: data)
        } else {
            return .default
        }
    }

    mutating func reloadConfiguration() {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview else { return }
        #endif
        
        guard let config = try? loadConfiguration() else {
            assertionFailure("Failed to reload configuration")
            return
        }

        self.configuration = config
    }
    
}
