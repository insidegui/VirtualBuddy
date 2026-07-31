//
//  GuestAppConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 19/06/25.
//

import SwiftUI
import VirtualCore

struct GuestAppConfigurationView: View {
    @Binding var configuration: VBMacConfiguration

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    private var guestAppStatus: ResolvedFeatureStatus? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.guestApp)?.status
    }

    private var guestAppUnsupported: Bool { guestAppStatus?.isUnsupported == true }
    private var guestAppHelp: String? {
        guestAppUnsupported ? (guestAppStatus?.supportMessage ?? "Not supported.") : nil
    }    

    private var availableGuestAppVersions: [CatalogLegacyGuestAppVersion] {
        SoftwareCatalog.currentMacCatalog.legacyGuestAppVersions
            .filter { $0.supports(resolvedRestoreImage) }
            .sorted(by: { $0.minGuestVersion > $1.minGuestVersion })
    }

    private var disableVersionPicker: Bool { availableGuestAppVersions.count <= 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let guestAppHelp {
                    Toggle("Enable VirtualBuddy Guest App", isOn: $configuration.guestAdditionsEnabled)
                        .disabled(true)
                        .help(guestAppHelp)
                } else {
                    Toggle("Enable VirtualBuddy Guest App", isOn: $configuration.guestAdditionsEnabled)
                }
            }
            .onChange(of: guestAppUnsupported) { _, isUnsupported in
                if isUnsupported {
                    configuration.guestAdditionsEnabled = false
                }
            }
            .onAppear {
                if guestAppUnsupported {
                    configuration.guestAdditionsEnabled = false
                }
            }

            /**
             The ability to pick a custom VirtualBuddyGuest app version exists to allow users running legacy OSes that don't have restore image
             metadata to manually override the version of the guest app that's used when starting the guest.
             */
            Picker("Override Guest App Version", selection: $configuration.guestAppVersion) {
                if CatalogLegacyGuestAppVersion.default.supports(resolvedRestoreImage) {
                    Text(CatalogLegacyGuestAppVersion.default.title)
                        .tag(Optional<CatalogLegacyGuestAppVersion.ID>.none)

                    Divider()
                }

                ForEach(availableGuestAppVersions) { option in
                    Text(option.title)
                        .tag(Optional<CatalogLegacyGuestAppVersion.ID>.some(option.id))
                }
            }
            .task {
                if !CatalogLegacyGuestAppVersion.default.supports(resolvedRestoreImage), configuration.guestAppVersion == nil {
                    configuration.guestAppVersion = availableGuestAppVersions.first(where: { $0.supports(resolvedRestoreImage) })?.id
                }
            }
            /// No point in enabling picker if there are no alternate versions available.
            .disabled(disableVersionPicker)
            .help(disableVersionPicker ? "This option is only available for guests running older versions of macOS that don’t support the latest VirtualBuddyGuest app." : "If you’re running an older version of macOS, you can choose a version of the VirtualBuddyGuest app that works with the version of macOS you’re using on the guest.")

            Text("""
            The guest app mounts shared directories and shares the clipboard between your Mac and virtual machines.

            To install the app in your virtual machine, look for a disk image named “Guest” in the Finder sidebar. \
            Double-click the VirtualBuddyGuest app icon to install the app. 
            """)
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
#Preview {
    _ConfigurationSectionPreview { GuestAppConfigurationView(configuration: $0) }
//        .environment(\.resolvedRestoreImage, ResolvedRestoreImage.previewMac)
}
#endif
