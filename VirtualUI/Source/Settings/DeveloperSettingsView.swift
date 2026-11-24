import MacDebugHost
import SwiftUI
import VirtualCore
import ManagedPreferencesUI

struct DeveloperSettingsView: View {
    @Binding var isEnabled: Bool
    var keys: any RegistrationKeyStore = XcodeProvisioningController.shared.keys
    var cache: DebugSymbolCache = VirtualBuddyDebugging.symbolCache

    @ManagedValue(for: .disableDeveloperFeatures, schema: VirtualBuddyManagedPreferences.schema, default: false)
    private var developerFeaturesDisabled: Bool

    var body: some View {
        SettingsPane {
            SettingsRow("Xcode debugging:") {
                Toggle("Enable developer features", isOn: developerFeaturesDisabled ? .constant(false) : $isEnabled)
                    .disabled(developerFeaturesDisabled)

                if developerFeaturesDisabled {
                    ManagedRestrictionBannerView(title: "Developer features are disabled by your organization.")
                } else {
                    SettingsCaption("Run and debug macOS apps from Xcode in your virtual machines.")
                }
            }

            if isEnabled && !developerFeaturesDisabled {
                SettingsDivider()
                DeviceRegistrationSettings(keys: keys)
            }
            DebugCacheSettings(showWhenEmpty: isEnabled && !developerFeaturesDisabled, cache: cache)
        }
        .task { cache.reload() }
    }
}

#if DEBUG
#Preview("Developer Settings") {
    @Previewable @State var enabled = true
    @Previewable @State var keys = PreviewRegistrationKeys()
    @Previewable @State var cache = DebugSymbolCache(
        root: URL.temporaryDirectory.appending(path: UUID().uuidString),
        helperURL: URL.temporaryDirectory.appending(path: "preview-symbol-helper")
    )
    DeveloperSettingsView(isEnabled: $enabled, keys: keys, cache: cache)
}
#endif
