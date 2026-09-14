import Foundation

/// Features supported by the guest OS and the configured guest app version.
public enum GuestAppSupport: Hashable, Sendable {
    case unsupported
    case sharedFoldersOnly
    case full

    public static let minimumSystemVersion: SoftwareVersion = "13"

    static func resolve(
        guestType: VBGuestType,
        guestVersion: SoftwareVersion?,
        latestMinimumVersion: SoftwareVersion,
        guestAppVersion: CatalogLegacyGuestAppVersion.ID?,
        legacyApps: [CatalogLegacyGuestAppVersion]
    ) -> Self {
        guard guestType == .mac else { return .unsupported }

        if let guestVersion, guestVersion > .empty {
            guard guestVersion >= minimumSystemVersion else { return .unsupported }
            if guestVersion < latestMinimumVersion { return .sharedFoldersOnly }
        } else if let legacy = legacyApps.first(where: { $0.id == guestAppVersion }),
                  legacy.minGuestVersion < legacy.maxGuestVersion,
                  legacy.maxGuestVersion <= minimumSystemVersion {
            // Imported VMs may only have an explicit legacy app selection to
            // identify their OS. Keep recognizing archived macOS 12 selections.
            return .unsupported
        }

        // An override selects an archived app, even on an OS that can run the
        // latest app. Archived apps cannot communicate with the current host.
        return guestAppVersion == nil ? .full : .sharedFoldersOnly
    }
}

public extension VBMacConfiguration {
    @MainActor
    func guestAppSupport(for guestVersion: SoftwareVersion?) -> GuestAppSupport {
        GuestAppSupport.resolve(
            guestType: systemType,
            guestVersion: guestVersion,
            latestMinimumVersion: Bundle.embeddedGuestApp.minimumSystemVersion,
            guestAppVersion: guestAppVersion,
            legacyApps: SoftwareCatalog.currentMacCatalog.legacyGuestAppVersions
        )
    }
}

@MainActor
extension VBVirtualMachine {
    var guestAppSupport: GuestAppSupport {
        let catalog = SoftwareCatalog.currentMacCatalog
        let version = [metadata.remoteInstallImageURL, metadata.installImageURL]
            .compactMap { $0 }
            .lazy.compactMap { catalog.resolvedRestoreImage(matching: $0, guestType: .mac)?.version }
            .first
        return configuration.guestAppSupport(for: version)
    }
}
