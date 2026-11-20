import SwiftUI
import VirtualCore
import ManagedPreferencesUI

struct DeveloperSettingsView: View {
    @Binding var isEnabled: Bool

    @ManagedValue(for: .disableDeveloperFeatures, schema: VirtualBuddyManagedPreferences.schema, default: false)
    private var developerFeaturesDisabled: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Enable Developer Features", isOn: developerFeaturesDisabled ? .constant(false) : $isEnabled)
                    .disabled(developerFeaturesDisabled)
            } footer: {
                if developerFeaturesDisabled {
                    ManagedRestrictionBannerView(title: "Developer features are disabled by your organization.")
                } else {
                    Text("Run and debug macOS apps from Xcode in your virtual machines.")
                }
            }

            DebugCacheSettings(showWhenEmpty: isEnabled && !developerFeaturesDisabled)
        }
        .navigationTitle(Text("Developer"))
        .onAppear { DebugSymbolCache.shared.reload() }
    }
}

#if DEBUG
#Preview("Developer Settings") {
    SettingsScreen.preview(.developer)
}
#endif
