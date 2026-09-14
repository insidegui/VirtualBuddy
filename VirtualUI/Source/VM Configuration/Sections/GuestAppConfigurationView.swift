//
//  GuestAppConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 19/06/25.
//

import SwiftUI
import VirtualCore
import ManagedPreferencesUI

struct GuestAppConfigurationView: View {
    @Binding var configuration: VBMacConfiguration

    @ManagedValue(for: .disableGuestApp, schema: VirtualBuddyManagedPreferences.schema, default: false)
    private var guestAppDisabled: Bool

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    private var guestAppStatus: ResolvedFeatureStatus? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.guestApp)?.status
    }

    private var support: GuestAppSupport {
        configuration.guestAppSupport(for: resolvedRestoreImage?.version)
    }

    private var guestAppUnsupported: Bool {
        support == .unsupported || guestAppStatus?.isUnsupported == true
    }

    private var availableGuestAppVersions: [CatalogLegacyGuestAppVersion] {
        SoftwareCatalog.currentMacCatalog.legacyGuestAppVersions
            .filter {
                // Preserve an existing override so imported VMs can display its
                // support status and let the user choose a supported version.
                $0.id == configuration.guestAppVersion
                    || ($0.maxGuestVersion > GuestAppSupport.minimumSystemVersion && $0.supports(resolvedRestoreImage))
            }
            .sorted(by: { $0.minGuestVersion > $1.minGuestVersion })
    }

    private var supportsLatest: Bool {
        CatalogLegacyGuestAppVersion.default.supports(resolvedRestoreImage)
    }

    private var disableVersionPicker: Bool {
        availableGuestAppVersions.count + (supportsLatest ? 1 : 0) <= 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable VirtualBuddy Guest App", isOn: guestAppDisabled ? .constant(false) : $configuration.guestAdditionsEnabled)
                .disabled(guestAppUnsupported || guestAppDisabled)
                .onChange(of: guestAppUnsupported, initial: true) { _, isUnsupported in
                    if isUnsupported {
                        configuration.guestAdditionsEnabled = false
                    }
                }

            if guestAppDisabled {
                ManagedRestrictionBannerView(title: "Guest app mounting is disabled by your organization.")
                Text("Restart the VM to apply. An already installed guest app is unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // The override also identifies the OS for imported VMs without
            // restore-image metadata. Keep it available for those VMs.
            if !guestAppUnsupported || resolvedRestoreImage == nil {
                Picker("Override Guest App Version", selection: $configuration.guestAppVersion) {
                    if supportsLatest {
                        Text(CatalogLegacyGuestAppVersion.default.title)
                            .tag(Optional<CatalogLegacyGuestAppVersion.ID>.none)
                    }

                    ForEach(availableGuestAppVersions) { option in
                        Text(option.title)
                            .tag(Optional<CatalogLegacyGuestAppVersion.ID>.some(option.id))
                    }
                }
                .onChange(of: resolvedRestoreImage, initial: true) { _, _ in
                    if !guestAppUnsupported, !supportsLatest, configuration.guestAppVersion == nil {
                        configuration.guestAppVersion = availableGuestAppVersions.first?.id
                    }
                }
                .disabled(disableVersionPicker)
                .help("Choose a compatible guest app version for an older version of macOS. Legacy guest apps support automatic mounting of shared folders only.")
            }

            VStack(alignment: .leading, spacing: 12) {
                if support == .unsupported {
                    Text("VirtualBuddyGuest is not supported on macOS 12 or earlier. Clipboard sharing and automatic mounting of shared folders are unavailable.")
                } else if guestAppUnsupported {
                    Text(guestAppStatus?.supportMessage ?? "VirtualBuddyGuest is not supported for this virtual machine.")
                } else {
                    switch support {
                    case .sharedFoldersOnly:
                        Text("This legacy version of VirtualBuddyGuest only mounts shared folders automatically. Clipboard sharing requires the latest VirtualBuddyGuest app and macOS \(Bundle.embeddedGuestApp.minimumSystemVersion.shortDescription) or later in the virtual machine.")
                    case .full:
                        Text("VirtualBuddyGuest mounts shared folders automatically and shares the clipboard between your Mac and the virtual machine.")
                    case .unsupported:
                        EmptyView()
                    }

                    Text("To install the app in your virtual machine, select the “Guest” disk in the Finder sidebar, then double-click the VirtualBuddyGuest app icon.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }
}

extension CatalogLegacyGuestAppVersion {
    /// A placeholder that represents the version that ships with this build of VirtualBuddy.
    ///
    /// - note: Use for UI purposes only, do not use as a source of truth.
    static let `default` = CatalogLegacyGuestAppVersion(
        id: "__DEFAULT__",
        url: Bundle.embeddedGuestApp.bundleURL,
        sha384: "",
        guestAppVersion: .embeddedGuestApp,
        minGuestVersion: Bundle.embeddedGuestApp.minimumSystemVersion,
        maxGuestVersion: SoftwareVersion(major: 99, minor: 99, patch: 99),
        minAppVersion: nil,
        maxAppVersion: nil
    )

    var isDefault: Bool { guestAppVersion == SoftwareVersion.embeddedGuestApp }

    var title: String { "\(isDefault ? "Latest" : guestAppVersion.shortDescription) (macOS \(minGuestVersion.shortDescription) or later)" }
}

#if DEBUG
#Preview("Latest Guest App") {
    _ConfigurationSectionPreview { GuestAppConfigurationView(configuration: $0) }
        .environment(\.resolvedRestoreImage, ResolvedRestoreImage.previewMac)
}

#Preview("macOS 13") {
    _ConfigurationSectionPreview { GuestAppConfigurationView(configuration: $0) }
        .environment(\.resolvedRestoreImage, ResolvedRestoreImage.previewMacLegacyVentura)
}

#Preview("macOS 12") {
    _ConfigurationSectionPreview { GuestAppConfigurationView(configuration: $0) }
        .environment(\.resolvedRestoreImage, ResolvedRestoreImage.previewMacLegacyMonterey)
}
#endif
