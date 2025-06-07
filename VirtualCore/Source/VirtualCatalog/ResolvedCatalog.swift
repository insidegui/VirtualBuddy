import Foundation
import BuddyFoundation
import OSLog

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "ResolvedCatalog")

public protocol ResolvedCatalogModel: Identifiable, Hashable, Sendable { }

/// Represents a ``SoftwareCatalog`` that's been processed in order to resolve
/// all channel and group members, as well as the supported features and requirement sets for the current environment.
public struct ResolvedCatalog: Hashable, Sendable {
    /// The resolved release groups.
    public var groups: [ResolvedCatalogGroup]
}

public struct ResolvedCatalogGroup: ResolvedCatalogModel {
    public var id: CatalogGroup.ID { group.id }
    public var group: CatalogGroup
    public var restoreImages: [ResolvedRestoreImage]

    public var name: String { group.name }
    public var majorVersion: SoftwareVersion { group.majorVersion }
    public var image: CatalogGraphic { group.image }
    public var darkImage: CatalogGraphic { group.darkImage ?? group.image }

    public init(group: CatalogGroup, restoreImages: [ResolvedRestoreImage]) {
        self.group = group
        self.restoreImages = restoreImages
    }
}

public struct ResolvedRestoreImage: ResolvedCatalogModel {
    public var id: RestoreImage.ID { image.id }
    public var image: RestoreImage
    public var channel: CatalogChannel
    public var features: [ResolvedVirtualizationFeature]
    public var requirements: ResolvedRequirementSet
    public var status: ResolvedFeatureStatus

    public var name: String { image.name }
    public var build: String { image.build }
    public var version: SoftwareVersion { image.version }
    public var mobileDeviceMinVersion: SoftwareVersion { image.mobileDeviceMinVersion }
    public var url: URL { image.url }
    public var downloadSize: Int64 { Int64(image.downloadSize ?? 0) }

    public init(image: RestoreImage, channel: CatalogChannel, features: [ResolvedVirtualizationFeature], requirements: ResolvedRequirementSet, status: ResolvedFeatureStatus) {
        self.image = image
        self.channel = channel
        self.features = features
        self.requirements = requirements
        self.status = status
    }
}

/// The status of a feature or requirement set for the current environment.
public enum ResolvedFeatureStatus: Hashable, Sendable {
    /// The feature is fully supported.
    case supported
    /// The feature is partially supported.
    case warning(message: String)
    /// The feature is not supported.
    case unsupported(message: String)

    var isSupported: Bool {
        if case .supported = self { true } else { false }
    }

    var message: String? {
        switch self {
        case .supported: return nil
        case .warning(let message), .unsupported(let message): return message
        }
    }
}

/// A feature that's been resolved for the current environment, indicating whether it is supported.
public struct ResolvedVirtualizationFeature: ResolvedCatalogModel {
    public var id: VirtualizationFeature.ID { feature.id }
    public var feature: VirtualizationFeature
    public var status: ResolvedFeatureStatus
}

/// A requirement set that's been resolved for the current environment.
public struct ResolvedRequirementSet: ResolvedCatalogModel {
    public var id: RequirementSet.ID { requirements.id }
    public var requirements: RequirementSet
    public var status: ResolvedFeatureStatus

    public init(requirements: RequirementSet, status: ResolvedFeatureStatus) {
        self.requirements = requirements
        self.status = status
    }
}

// MARK: - Catalog Resolution

/// Represents a guest platform such as Mac or Linux.
/// Not an enum just in case more platforms are added in the future (iOS? 🤞🏻)
public struct CatalogGuestPlatform: ResolvedCatalogModel, RawRepresentable, CaseIterable, CustomStringConvertible {
    public typealias RawValue = String
    public var rawValue: String { id }

    public var id: String
    public var name: String

    public static let mac = CatalogGuestPlatform(id: "mac", name: "Mac")
    public static let linux = CatalogGuestPlatform(id: "linux", name: "Linux")
    public static let unknown = CatalogGuestPlatform(id: "_unknown", name: "Unknown")

    public static let allCases: [CatalogGuestPlatform] = [.mac, .linux]

    public init(rawValue: String) {
        if let platform = Self.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }) {
            self = platform
        } else {
            assertionFailure("Unsupported platform \"\(rawValue)\"")
            self = .unknown
        }
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var description: String { id }
}

/// Properties used when resolving a catalog for a given environment.
/// These are used to assess the support status for different features/requirements.
public struct CatalogResolutionEnvironment: Sendable {
    /// The host OS version.
    public var hostVersion: SoftwareVersion
    /// The guest OS version.
    public var guestVersion: SoftwareVersion
    /// The guest OS platform.
    public var guestPlatform: CatalogGuestPlatform
    /// The version of the host app.
    public var appVersion: SoftwareVersion
    /// The version of the MobileDevice framework on the host.
    public var mobileDeviceVersion: SoftwareVersion
    /// The number of CPU cores configured for the VM.
    /// Can be set to nil if performing resolution before configuration,
    /// in which case the requirement set will be considered as satisfied.
    public var cpuCoreCount: Int?
    /// The number of CPU cores configured for the VM.
    /// Can be set to nil if performing resolution before configuration,
    /// in which case the requirement set will be considered as satisfied.
    public var memorySizeMB: Int?

    public init(hostVersion: SoftwareVersion, guestVersion: SoftwareVersion, guestPlatform: CatalogGuestPlatform, appVersion: SoftwareVersion, mobileDeviceVersion: SoftwareVersion, cpuCoreCount: Int? = nil, memorySizeMB: Int? = nil) {
        self.hostVersion = hostVersion
        self.guestVersion = guestVersion
        self.guestPlatform = guestPlatform
        self.appVersion = appVersion
        self.mobileDeviceVersion = mobileDeviceVersion
        self.cpuCoreCount = cpuCoreCount
        self.memorySizeMB = memorySizeMB
    }
}

public extension ResolvedCatalog {
    init(environment: CatalogResolutionEnvironment, catalog: SoftwareCatalog) throws {
        self.groups = catalog.groups.map { group in
            let images = catalog.restoreImages.filter({ $0.group == group.id })

            /// Resolve images one by one to prevent error on single image from taking down entire catalog.
            var resolvedImages = [ResolvedRestoreImage]()
            for image in images {
                do {
                    let resolvedImage = try ResolvedRestoreImage(environment: environment, catalog: catalog, image: image)
                    resolvedImages.append(resolvedImage)
                } catch {
                    logger.error("Error resolving image \(image.id, privacy: .public) - \(error, privacy: .public)")
                }
            }

            return ResolvedCatalogGroup(group: group, restoreImages: resolvedImages)
        }
    }
}

public extension ResolvedRestoreImage {
    init(environment: CatalogResolutionEnvironment, catalog: SoftwareCatalog, image: RestoreImage) throws {
        try self.init(
            image: image,
            channel: catalog.channel(with: image.channel),
            features: catalog.features.map { ResolvedVirtualizationFeature(feature: $0, status: .supported) },
            requirements: ResolvedRequirementSet(requirements: catalog.requirementSet(with: image.requirements), status: .supported),
            status: .supported
        )

        update(with: environment)
    }

    mutating func update(with environment: CatalogResolutionEnvironment) {
        /// Adds the guest OS version to the environment so that features/requirements that depend on it get the correct status.
        let versionedEnvironment = environment.guest(version: image.version)

        if versionedEnvironment.mobileDeviceVersion < image.mobileDeviceMinVersion {
            self.status = .mobileDeviceOutdated
        }

        features = features.map { $0.updated(with: versionedEnvironment) }

        requirements.update(with: versionedEnvironment)
    }
}

public extension ResolvedVirtualizationFeature {
    mutating func update(with environment: CatalogResolutionEnvironment) {
        guard !feature.unsupportedPlatform else {
            self.status = .unsupportedGuestPlatform(feature, platform: environment.guestPlatform)
            return
        }

        guard environment.hostVersion >= self.feature.minVersionHost else {
            self.status = .unsupportedHost(feature)
            return
        }
        guard environment.guestVersion >= self.feature.minVersionGuest else {
            self.status = .unsupportedGuest(feature)
            return
        }
        self.status = .supported
    }

    func updated(with environment: CatalogResolutionEnvironment) -> Self {
        var mSelf = self
        mSelf.update(with: environment)
        return mSelf
    }
}

public extension ResolvedRequirementSet {
    mutating func update(with environment: CatalogResolutionEnvironment) {
        guard environment.hostVersion >= self.requirements.minVersionHost else {
            self.status = .unsupportedHost(requirements)
            return
        }
        self.status = .supported
    }

    func updated(with environment: CatalogResolutionEnvironment) -> Self {
        var mSelf = self
        mSelf.update(with: environment)
        return mSelf
    }
}

extension ResolvedFeatureStatus {
    static func unsupported(_ message: String?...) -> Self {
        .unsupported(message: message.compactMap({ $0 }).joined(separator: " "))
    }

    static func unsupportedHost(_ feature: VirtualizationFeature) -> Self {
        .unsupported("\(feature.name) requires the host to be running macOS \(feature.minVersionHost.shortDescription) or later.", feature.detail)
    }

    static func unsupportedGuest(_ feature: VirtualizationFeature) -> Self {
        .unsupported("\(feature.name) only works in virtual machines running macOS \(feature.minVersionHost.shortDescription) or later.", feature.detail)
    }

    static func unsupportedGuestPlatform(_ feature: VirtualizationFeature, platform: CatalogGuestPlatform) -> Self {
        .unsupported("\(feature.name) is not available on \(platform.name) guests.", feature.detail)
    }

    static func unsupportedHost(_ requirements: RequirementSet) -> Self {
        .unsupported("This version of macOS requires the host to be running macOS \(requirements.minVersionHost.shortDescription) or later.")
    }

    static var mobileDeviceOutdated: Self {
        .warning(message: "This version of macOS requires device support files which are not currently installed on your system.")
    }
}

struct CatalogError: LocalizedError, CustomStringConvertible {
    var errorDescription: String?
    init(_ errorDescription: String) {
        self.errorDescription = errorDescription
    }
    var description: String { errorDescription ?? "" }
}

public extension SoftwareCatalog {
    func group(with id: CatalogGroup.ID) throws -> CatalogGroup {
        guard let group = groups.first(where: { $0.id == id }) else {
            throw CatalogError("Group not found with id \"\(id)\"")
        }
        return group
    }
    func channel(with id: CatalogGroup.ID) throws -> CatalogChannel {
        guard let channel = channels.first(where: { $0.id == id }) else {
            throw CatalogError("Channel not found with id \"\(id)\"")
        }
        return channel
    }
    func requirementSet(with id: RequirementSet.ID) throws -> RequirementSet {
        guard let requirements = requirementSets.first(where: { $0.id == id }) else {
            throw CatalogError("Requirement set not found with id \"\(id)\"")
        }
        return requirements
    }
}

public extension CatalogResolutionEnvironment {
    static let current: CatalogResolutionEnvironment = {
        CatalogResolutionEnvironment(
            hostVersion: .currentHost,
            guestVersion: .currentHost,
            guestPlatform: .mac,
            appVersion: .init(major: 2, minor: 0, patch: 0),
            mobileDeviceVersion: MobileDeviceFramework.current?.version ?? .init(major: 0, minor: 0, patch: 0)
        )
    }()

    func guest(platform: CatalogGuestPlatform, version: SoftwareVersion) -> Self {
        var mSelf = self
        mSelf.guestPlatform = platform
        mSelf.guestVersion = version
        return mSelf
    }

    func guest(platform: CatalogGuestPlatform) -> Self {
        var mSelf = self
        mSelf.guestPlatform = platform
        return mSelf
    }

    func guest(version: SoftwareVersion) -> Self {
        var mSelf = self
        mSelf.guestVersion = version
        return mSelf
    }
}

extension SoftwareVersion {
    static let currentHost: SoftwareVersion = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return SoftwareVersion(major: v.majorVersion, minor: v.minorVersion, patch: v.patchVersion)
    }()
}
