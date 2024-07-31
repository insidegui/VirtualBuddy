import Foundation

/// Adopted by all models present in a VirtualBuddy software catalog.
public protocol CatalogModel: Identifiable, Hashable, Codable, Sendable { }

/// Defines a set of requirements a given software image needs from the virtual machine in order to work.
public struct RequirementSet: CatalogModel {
    /// Identifies the requirement set, used to reference a requirement set from a software image definition.
    public var id: String
    /// The minimum number of CPU cores.
    public var minCPUCount: Int
    /// The minimum amount of RAM the VM needs.
    public var minMemorySizeMB: Int
    /// The minimum host operating system version required to run the system.
    public var minVersionHost: SoftwareVersion

    public init(id: String, minCPUCount: Int, minMemorySizeMB: Int, minVersionHost: SoftwareVersion) {
        self.id = id
        self.minCPUCount = minCPUCount
        self.minMemorySizeMB = minMemorySizeMB
        self.minVersionHost = minVersionHost
    }
}

/// Defines a feature of Virtualization and its associated requirements.
public struct VirtualizationFeature: CatalogModel {
    /// Identifies the feature, used to reference a feature from a software image definition.
    public var id: String
    /// The minimum guest OS version required to use the feature.
    public var minVersionGuest: SoftwareVersion
    /// The minimum host OS version required to use the feature.
    public var minVersionHost: SoftwareVersion
    /// A user-facing name for the feature, which is used in the beginning of a phrase like `<Trackpad> requires macOS xx.xx...`.
    public var name: String
    /// Additional information displayed when the feature is not supported by the current configuration.
    public var detail: String?

    public init(id: String, minVersionGuest: SoftwareVersion, minVersionHost: SoftwareVersion, name: String, detail: String? = nil) {
        self.id = id
        self.minVersionGuest = minVersionGuest
        self.minVersionHost = minVersionHost
        self.name = name
        self.detail = detail
    }
}

/// Defines an image that can be referenced by other items in the catalog.
/// Currently used to represent macOS release groups by the corresponding default wallpaper image.
public struct CatalogGraphic: CatalogModel {
    public struct Thumbnail: Hashable, Codable, Sendable {
        public var url: URL
        public var width: Int
        public var height: Int
        public var blurHash: String

        public init(url: URL, width: Int, height: Int, blurHash: String) {
            self.url = url
            self.width = width
            self.height = height
            self.blurHash = blurHash
        }
    }

    /// Identifies the graphic, used to reference a graphic from another catalog model.
    public var id: String
    /// URL to the graphic image file, in its highest resolution.
    public var url: URL
    /// Thumbnail representation of the image, with metadata and blur hash.
    public var thumbnail: Thumbnail

    public init(id: String, url: URL, thumbnail: Thumbnail) {
        self.id = id
        self.url = url
        self.thumbnail = thumbnail
    }
}

/// Defines a grouping of software images by major OS version.
/// This can be used to group releases like `macOS Sonoma`, `macOS Sequoia`, etc,
/// making it easier for users to find the desired OS version.
public struct CatalogGroup: CatalogModel {
    /// Identifies the group, used to reference a group from a software image definition.
    public var id: String
    /// A user-facing name for the release group.
    public var name: String
    /// The major OS version for releases in this group.
    public var majorVersion: SoftwareVersion
    /// The image that can be used to represent this group.
    public var image: CatalogGraphic
    /// The image that can be used to represent this group when dark mode is enabled.
    public var darkImage: CatalogGraphic?

    public init(id: String, name: String, majorVersion: SoftwareVersion, image: CatalogGraphic, darkImage: CatalogGraphic?) {
        self.id = id
        self.name = name
        self.majorVersion = majorVersion
        self.image = image
        self.darkImage = darkImage
    }
}

/// Defines a release channel such as `Beta` or `Release`.
/// Can be used to allow filtering for specific release types.
public struct CatalogChannel: CatalogModel {
    /// Identifies the channel, used to reference a channel from a software image definition.
    public var id: String
    /// User-facing name for the channel.
    public var name: String
    /// User-facing note describing the contents in this channel.
    public var note: String
    /// SF Symbol name for icon that can be used to represent this channel.
    public var icon: String

    public init(id: String, name: String, note: String, icon: String) {
        self.id = id
        self.name = name
        self.note = note
        self.icon = icon
    }
}

/// Defines an individual macOS restore image in the catalog.
public struct RestoreImage: CatalogModel {
    /// Unique identifier for this restore image.
    public var id: String
    /// Identifier of the ``CatalogGroup`` this restore image is a part of.
    public var group: CatalogGroup.ID
    /// Identifier of the ``CatalogChannel`` this restore image is a part of.
    public var channel: CatalogChannel.ID
    /// Identifier of the ``RequirementSet`` describing the requirements for this image to be installed/run.
    public var requirements: RequirementSet.ID
    /// User-facing name for this restore image, usually in a form like `macOS 15.0 Developer Beta 4`.
    public var name: String
    /// OS build this restore image provides.
    public var build: String
    /// OS version this restore image provides.
    public var version: SoftwareVersion
    /// The minimum version of the MobileDevice framework required to install this guest.
    public var mobileDeviceMinVersion: SoftwareVersion
    /// URL to the IPSW file for this restore image.
    public var url: URL

    public init(id: String, group: CatalogGroup.ID, channel: CatalogChannel.ID, requirements: RequirementSet.ID, name: String, build: String, version: SoftwareVersion, mobileDeviceMinVersion: SoftwareVersion, url: URL) {
        self.id = id
        self.group = group
        self.channel = channel
        self.requirements = requirements
        self.name = name
        self.build = build
        self.version = version
        self.mobileDeviceMinVersion = mobileDeviceMinVersion
        self.url = url
    }
}

/// This is the root data structure for the VirtualBuddy restore image catalog.
public struct SoftwareCatalog: Codable, Sendable {
    /// The API version implemented by this software catalog.
    public var apiVersion: Int
    /// The minimum verson of the app that can read this catalog.
    /// The app should reject catalogs with a higher `minAppVersion` and
    /// direct users to update the app in order to use the catalog.
    public var minAppVersion: SoftwareVersion
    /// Channel definitions.
    public var channels: [CatalogChannel]
    /// Release group definitions.
    public var groups: [CatalogGroup]
    /// Restore image definitions.
    public var restoreImages: [RestoreImage]
    /// Feature definitions.
    public var features: [VirtualizationFeature]
    /// Requirement set definitions.
    public var requirementSets: [RequirementSet]

    public init(apiVersion: Int, minAppVersion: SoftwareVersion, channels: [CatalogChannel], groups: [CatalogGroup], restoreImages: [RestoreImage], features: [VirtualizationFeature], requirementSets: [RequirementSet]) {
        self.apiVersion = apiVersion
        self.minAppVersion = minAppVersion
        self.channels = channels
        self.groups = groups
        self.restoreImages = restoreImages
        self.features = features
        self.requirementSets = requirementSets
    }
}

public extension SoftwareCatalog {
    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        return e
    }()

    init(data: Data) throws {
        self = try Self.decoder.decode(Self.self, from: data)
    }

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }

    func write(to url: URL) throws {
        try Self.encoder.encode(self).write(to: url)
    }
}

public extension CatalogGraphic {
    static let placeholder = CatalogGraphic(
        id: "placeholder",
        url: URL(string: "https://example.com")!,
        thumbnail: Thumbnail(url: URL(string: "https://example.com")!, width: 640, height: 360, blurHash: "XXX")
    )
}
