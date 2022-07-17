import Foundation
import UniformTypeIdentifiers

public struct VBVirtualMachine: Identifiable, Hashable {
    
    public struct Metadata: Hashable, Codable {
        public internal(set) var operatingSystemVersion: String
        public internal(set) var operatingSystemBuild: String
        public internal(set) var xCodeVersion: String?
        public internal(set) var NVRAM = [VBNVRAMVariable]()
    }
    
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
    
    public internal(set) var metadata: Metadata

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
    static let preview = VBVirtualMachine(
        bundleURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Sample.vbvm"),
        installOptions: InstallOptions(diskImageSize: .defaultDiskImageSize),
        metadata: Metadata(
            operatingSystemVersion: "12.4",
            operatingSystemBuild: "XYZ123",
            xCodeVersion: "13.3.1 (13E500a)",
            NVRAM: [.init(name: "boot-args", value: "amfi_get_out_of_my_way=1 cs_debug=1")]
        )
    )
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
    
    var metadataFileURL: URL { Self.metadataFileURL(for: bundleURL) }
    
    static func metadataDirectoryURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(".vbdata")
    }
    
    static func metadataFileURL(for bundleURL: URL) -> URL {
        metadataDirectoryURL(for: bundleURL)
            .appendingPathComponent("metadata.plist")
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
        self.metadata = try Metadata(bundleURL: bundleURL)
    }
    
}

extension VBVirtualMachine.Metadata {
    
    init(bundleURL: URL) throws {
        let fileURL = VBVirtualMachine.metadataFileURL(for: bundleURL)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: bundleURL)
            self = try PropertyListDecoder().decode(VBVirtualMachine.Metadata.self, from: data)
        } else {
            self.init(operatingSystemVersion: "??", operatingSystemBuild: "??", xCodeVersion: nil, NVRAM: [])
        }
    }
    
}
