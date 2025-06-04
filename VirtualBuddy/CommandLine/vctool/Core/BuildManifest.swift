import Foundation
import BuddyFoundation

struct BuildManifest: Decodable, TreeStringConvertible {
    var manifestVersion: Int
    var productBuildVersion: String
    var productVersion: SoftwareVersion
    var supportedProductTypes: [String]
    var buildIdentities: [BuildIdentity]
    
    enum CodingKeys: String, CodingKey {
        case manifestVersion = "ManifestVersion"
        case productBuildVersion = "ProductBuildVersion"
        case productVersion = "ProductVersion"
        case supportedProductTypes = "SupportedProductTypes"
        case buildIdentities = "BuildIdentities"
    }
}

struct BuildIdentity: Decodable, TreeStringConvertible {
    var productMarketingVersion: SoftwareVersion
    var boardID: String
    var chipID: String
    var uniqueBuildID: Data
    var info: BuildInfo

    enum CodingKeys: String, CodingKey {
        case productMarketingVersion = "ProductMarketingVersion"
        case boardID = "ApBoardID"
        case chipID = "ApChipID"
        case uniqueBuildID = "UniqueBuildID"
        case info = "Info"
    }
}

struct BuildInfo: Decodable, TreeStringConvertible {
    var buildNumber: String
    var buildTrain: String
    var deviceClass: String
    var restoreBehavior: String
    var variant: String
    var mobileDeviceMinVersion: SoftwareVersion
    var virtualMachineMinCPUCount: Int?
    var virtualMachineMinHostOS: SoftwareVersion?
    var virtualMachineMinMemorySizeMB: Int?

    enum CodingKeys: String, CodingKey {
        case buildNumber = "BuildNumber"
        case buildTrain = "BuildTrain"
        case deviceClass = "DeviceClass"
        case restoreBehavior = "RestoreBehavior"
        case variant = "Variant"
        case virtualMachineMinCPUCount = "VirtualMachineMinCPUCount"
        case virtualMachineMinHostOS = "VirtualMachineMinHostOS"
        case virtualMachineMinMemorySizeMB = "VirtualMachineMinMemorySizeMB"
        case mobileDeviceMinVersion = "MobileDeviceMinVersion"
    }

}

// MARK: - Parsing

extension BuildManifest {
    private static let decoder: PropertyListDecoder = {
        let d = PropertyListDecoder()
        return d
    }()

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: data)
    }

    init(data: Data) throws {
        self = try Self.decoder.decode(Self.self, from: data)
    }
}

// MARK: - Filtering

extension BuildManifest {
    mutating func filterBuildIdentities(using predicate: (BuildIdentity) -> Bool) {
        buildIdentities.removeAll(where: { !predicate($0) })
    }

    func filteringBuildIdentities(using predicate: (BuildIdentity) -> Bool) -> BuildManifest {
        var mSelf = self
        mSelf.filterBuildIdentities(using: predicate)
        return mSelf
    }
}

extension BuildInfo {
    /// `true` if the information indicates that the associated build identity is for a Mac VM.
    var hasVMInformation: Bool {
        virtualMachineMinHostOS != nil
        || virtualMachineMinCPUCount != nil
        || virtualMachineMinMemorySizeMB != nil
        || deviceClass.caseInsensitiveCompare("vma2macosap") == .orderedSame
    }
}

extension BuildIdentity {
    /// `true` if the information indicates that this build identity is for a Mac VM.
    var hasVMInformation: Bool { info.hasVMInformation }
}
