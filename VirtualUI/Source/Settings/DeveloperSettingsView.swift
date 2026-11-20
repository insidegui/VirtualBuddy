import SwiftUI
import VirtualCore

struct DeveloperSettingsView: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Enable Developer Features", isOn: $isEnabled)
            } footer: {
                Text("Run and debug macOS apps from Xcode in your virtual machines.")
            }

            DebugCacheSettings(showWhenEmpty: isEnabled)
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
