import Foundation
import UniformTypeIdentifiers
import Combine

public typealias VoidSubject = PassthroughSubject<(), Never>

public struct VBVirtualMachine: Identifiable {

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

    public private(set) var didInvalidateThumbnail = VoidSubject()
    
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

    static let configurationFilename = "Config.plist"
    
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

    static func metadataDirectoryURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(".vbdata")
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
        self.configuration = try loadConfiguration()

        try saveConfiguration()
    }

    func saveConfiguration() throws {
        let configData = try PropertyListEncoder().encode(configuration)
        try write(configData, forMetadataFileNamed: Self.configurationFilename)
    }

    func loadConfiguration() throws -> VBMacConfiguration {
        if let data = metadataContents(Self.configurationFilename) {
            return try PropertyListDecoder().decode(VBMacConfiguration.self, from: data)
        } else {
            return .default
        }
    }

    mutating func reloadConfiguration() {
        guard let config = try? loadConfiguration() else {
            assertionFailure("Failed to reload configuration")
            return
        }

        self.configuration = config
    }
    
}
