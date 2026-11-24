import SwiftUI
import VirtualCore
import ManagedPreferencesUI

struct DeveloperSettingsView: View {
    @Binding var isEnabled: Bool

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
                DeviceRegistrationSettings()
            }
            DebugCacheSettings(showWhenEmpty: isEnabled && !developerFeaturesDisabled)
        }
        .task { VirtualBuddyDebugging.symbolCache.reload() }
    }
}

#if DEBUG
#Preview("Developer Settings") {
    SettingsScreen.preview(.developer)
}
#endif
