import Foundation
import UniformTypeIdentifiers

public struct VBVirtualMachine: Identifiable, Hashable {

    public struct InstallOptions: Hashable {
        public let diskImageSize: Int
        
        public init(diskImageSize: Int) {
            self.diskImageSize = diskImageSize
        }
    }
    
    public var id: String { bundleURL.absoluteString }
    public let bundleURL: URL
    public var name: String { bundleURL.deletingPathExtension().lastPathComponent }
    public var installOptions: InstallOptions?
    private var _configuration: VBMacConfiguration?
    
    public var configuration: VBMacConfiguration {
        /// Masking private `_configuration` to avoid making the public API optional
        /// without having to do any special `Codable` shenanigans.
        get { _configuration ?? .default }
        set { _configuration = newValue }
    }
}

public extension VBVirtualMachine {
    static let bundleExtension = "vbvm"
    static let screenshotFileName = "Screenshot.tiff"
    static let thumbnailFileName = "Thumbnail.jpg"
}

public extension VBVirtualMachine {
    static let preview: VBVirtualMachine =  {
        try! VBVirtualMachine(
            bundleURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Sample.vbvm"),
            installOptions: InstallOptions(diskImageSize: .defaultDiskImageSize)
        )
    }()
}

extension VBVirtualMachine {
    
    var diskImagePath: String {
        bundleURL.appendingPathComponent("Disk.img").path
    }
    
    var extraDiskImagePath: String {
        bundleURL.appendingPathComponent("Disk2.img").path
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
    
    var configFileURL: URL { Self.configurationFileURL(for: bundleURL) }
    
    static func metadataDirectoryURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(".vbdata")
    }
    
    static func metadataFileURL(for bundleURL: URL) -> URL {
        metadataDirectoryURL(for: bundleURL)
            .appendingPathComponent("metadata.plist")
    }

    static func configurationFileURL(for bundleURL: URL) -> URL {
        metadataDirectoryURL(for: bundleURL)
            .appendingPathComponent("config.plist")
    }

}

public extension UTType {
    static let virtualBuddyVM = UTType(exportedAs: "codes.rambo.VirtualBuddy.VM", conformingTo: .bundle)
}

public extension VBVirtualMachine {
    
    init(bundleURL: URL, installOptions: InstallOptions? = nil) throws {
        if !FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        }
        
        self.bundleURL = bundleURL
        self.installOptions = installOptions

        if FileManager.default.fileExists(atPath: configFileURL.path) {
            let data = try Data(contentsOf: configFileURL)
            self.configuration = try PropertyListDecoder().decode(VBMacConfiguration.self, from: data)
        } else {
            self.configuration = .default
        }
    }
    
}
