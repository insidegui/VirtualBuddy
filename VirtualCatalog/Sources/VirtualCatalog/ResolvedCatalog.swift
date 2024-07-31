import Foundation

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
}

public struct ResolvedRestoreImage: ResolvedCatalogModel {
    public var id: RestoreImage.ID { image.id }
    public var image: RestoreImage
    public var channel: CatalogChannel
    public var features: [ResolvedVirtualizationFeature]
    public var requirements: ResolvedRequirementSet
    public var status: ResolvedFeatureStatus
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
}

// MARK: - Catalog Resolution

/// Properties used when resolving a catalog for a given environment.
/// These are used to assess the support status for different features/requirements.
public struct CatalogResolutionEnvironment: Sendable {
    /// The host OS version.
    public var hostVersion: SoftwareVersion
    /// The guest OS version.
    public var guestVersion: SoftwareVersion
    /// The version of the host app.
    public var appVersion: SoftwareVersion
    /// The version of the MobileDevice framework on the host.
    public var mobileDeviceVersion: SoftwareVersion
    /// The number of CPU cores configured for the VM.
    /// Can be set to nil if performing resolution before configuration,
    /// in which case the requirement set will be considered as satistied.
    public var cpuCoreCount: Int?
    /// The number of CPU cores configured for the VM.
    /// Can be set to nil if performing resolution before configuration,
    /// in which case the requirement set will be considered as satistied.
    public var memorySizeMB: Int?

    public init(hostVersion: SoftwareVersion, guestVersion: SoftwareVersion, appVersion: SoftwareVersion, mobileDeviceVersion: SoftwareVersion, cpuCoreCount: Int? = nil, memorySizeMB: Int? = nil) {
        self.hostVersion = hostVersion
        self.guestVersion = guestVersion
        self.appVersion = appVersion
        self.mobileDeviceVersion = mobileDeviceVersion
        self.cpuCoreCount = cpuCoreCount
        self.memorySizeMB = memorySizeMB
    }
}

public extension ResolvedCatalog {
    init(environment: CatalogResolutionEnvironment, catalog: SoftwareCatalog) throws {
        self.groups = try catalog.groups.map { group in
            let images = catalog.restoreImages.filter({ $0.group == group.id })
            let resolvedImages = try images.map { try ResolvedRestoreImage(environment: environment, catalog: catalog, image: $0) }
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
        let versionedEnvironment = environment.guest(image.version)

        if versionedEnvironment.mobileDeviceVersion < image.mobileDeviceMinVersion {
            self.status = .mobileDeviceOutdated
        }

        features = features.map { $0.updated(with: versionedEnvironment) }

        requirements.update(with: versionedEnvironment)
    }
}

public extension ResolvedVirtualizationFeature {
    mutating func update(with environment: CatalogResolutionEnvironment) {
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
        .unsupported("\(feature.name) requires the host to be running macOS \(feature.minVersionHost) or later.", feature.detail)
    }

    static func unsupportedGuest(_ feature: VirtualizationFeature) -> Self {
        .unsupported("\(feature.name) only works in virtual machines running macOS \(feature.minVersionHost) or later.", feature.detail)
    }

    static func unsupportedHost(_ requirements: RequirementSet) -> Self {
        .unsupported("This version of macOS requires the host to be running macOS \(requirements.minVersionHost) or later.")
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
            appVersion: .init(major: 2, minor: 0, patch: 0),
            mobileDeviceVersion: MobileDeviceFramework.current?.version ?? .init(major: 0, minor: 0, patch: 0)
        )
    }()

    func guest(_ version: SoftwareVersion) -> Self {
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