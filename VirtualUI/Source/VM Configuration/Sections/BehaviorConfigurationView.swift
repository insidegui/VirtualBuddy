import SwiftUI
import VirtualCore

/// Configures what happens to the virtual machine when its window is closed, when the app quits, and when the app launches.
struct BehaviorConfigurationView: View {
    @Binding var configuration: VBMacConfiguration

    /// The global settings are shown next to the option that follows them, so that it's clear what that option does.
    @ObservedObject private var settingsContainer = VBSettingsContainer.current

    private var settings: VBSettings { settingsContainer.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("When closing the window", selection: $configuration.closeBehaviorOverride) {
                Text("Use global setting (\(settings.closeBehavior.title))")
                    .tag(Optional<VMCloseBehavior>.none)

                Divider()

                ForEach(VMCloseBehavior.allCases) { behavior in
                    Text(behavior.title)
                        .tag(Optional(behavior))
                }
            }

            Picker("When quitting VirtualBuddy", selection: $configuration.quitBehaviorOverride) {
                Text("Use global setting (\(settings.quitBehavior.title))")
                    .tag(Optional<VMQuitBehavior>.none)

                Divider()

                ForEach(VMQuitBehavior.allCases) { behavior in
                    Text(behavior.title)
                        .tag(Optional(behavior))
                }
            }

            Toggle("Start in the background when VirtualBuddy launches", isOn: $configuration.autoBootInBackground)

            VStack(alignment: .leading, spacing: 12) {
                Text("Save state keeps the virtual machine as it is so that it continues where you left off. This feature is only available for macOS guests.")

                Text("A virtual machine that keeps running in the background has no window. Open it from the library to show its window again.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    _ConfigurationSectionPreview { BehaviorConfigurationView(configuration: $0) }
}
#endif
