import Foundation

/// Uses the same restore-image metadata and legacy-app selection as the guest
/// installer. An old app selection never overrides a known supported OS version.
enum LegacyClipboardEligibility {
    static func isRequired(guestType: VBGuestType, guestVersion: SoftwareVersion?,
                           minimumVersion: SoftwareVersion, selectedLegacyApp: CatalogLegacyGuestAppVersion?) -> Bool {
        guard guestType == .mac, minimumVersion > .empty else { return false }
        if let guestVersion, guestVersion > .empty { return guestVersion < minimumVersion }
        // Older imported VMs can lack restore-image metadata. The existing picker
        // is their explicit OS compatibility declaration; accept only ranges
        // entirely below the current guest app's minimum OS.
        guard let selectedLegacyApp else { return false }
        return selectedLegacyApp.minGuestVersion < selectedLegacyApp.maxGuestVersion
            && selectedLegacyApp.maxGuestVersion <= minimumVersion
    }
}

@MainActor
extension VBVirtualMachine {
    var requiresLegacyClipboard: Bool {
        guard configuration.systemType == .mac else { return false }
        let catalog = SoftwareCatalog.currentMacCatalog
        let version = [metadata.remoteInstallImageURL, metadata.installImageURL]
            .compactMap { $0 }
            .lazy.compactMap { catalog.resolvedRestoreImage(matching: $0, guestType: .mac)?.version }
            .first
        let legacy = catalog.legacyGuestAppVersions.first { $0.id == configuration.guestAppVersion }
        return LegacyClipboardEligibility.isRequired(guestType: configuration.systemType, guestVersion: version,
            minimumVersion: Bundle.embeddedGuestApp.minimumSystemVersion, selectedLegacyApp: legacy)
    }
}
