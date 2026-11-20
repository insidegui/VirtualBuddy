//
//  GeneralSettingsView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/06/25.
//

import SwiftUI
import VirtualCore
import BuddyUI

struct GeneralSettingsView: View {
    @Binding var settings: VBSettings
    @Binding var enableAutomaticUpdates: Bool
    @State private var alert = AlertContent()

    var body: some View {
        SettingsPane {
            SettingsRow("Library location:") {
                FileSystemPathFormControl(
                    url: settings.libraryURL,
                    contentTypes: [.folder],
                    defaultDirectoryKey: "library",
                    setURL: setLibraryURL
                )
                SettingsCaption("VirtualBuddy saves your virtual machines and downloaded installer images here.")
            }

            SettingsDivider()

            SettingsRow("When closing a VM:") {
                Picker("When closing a running virtual machine", selection: $settings.closeBehavior) {
                    ForEach(VMCloseBehavior.allCases) { behavior in
                        Text(behavior.title)
                            .tag(behavior)
                    }
                }
                .labelsHidden()
                .fixedSize()
                SettingsCaption("Save state lets you resume where you left off. This option is available only for macOS guests.")
            }

            SettingsDivider()

            SettingsRow("App updates:") {
                Toggle("Automatically check for updates", isOn: $enableAutomaticUpdates)
            }
            SettingsRow("Beta updates:") {
                if settings.updateChannel == .beta {
                    Button("Disable Beta Updates", action: confirmDisableBeta)
                } else {
                    Button("Join Beta…", action: confirmJoinBeta)
                }
            }
        }
        .alert($alert)
    }

    private func setLibraryURL(_ url: URL) {
        if let errorMessage = url.performWriteTest() {
            alert = AlertContent(errorMessage)
        } else {
            settings.libraryURL = url
        }
    }

    private func confirmDisableBeta() {
        if AppUpdateChannel.defaultChannel(for: .current) == .beta {
            /// If beta is disabled while running a beta release, user needs to reinstall release build manually.
            confirmDisableBetaNeedsReinstall()
        } else {
            /// If beta is disabled while running a non-beta release, no further action is needed.
            settings.updateChannel = .release
        }
    }

    /// Shown when user disables beta while running a beta release, which requires reinstalling a release version
    /// in order to effectivelly get out of the beta train.
    private func confirmDisableBetaNeedsReinstall() {
        let alert = NSAlert()
        alert.messageText = "Disable VirtualBuddy Beta"
        alert.informativeText = "In order to go back to the release version of VirtualBuddy, please download the latest release from GitHub and replace the current version you have installed."
        alert.addButton(withTitle: "Open Website")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        settings.updateChannel = .release

        guard let url = URL(string: "https://github.com/insidegui/VirtualBuddy/releases/latest") else { return }

        NSWorkspace.shared.open(url)
    }

    private func confirmJoinBeta() {
        let alert = NSAlert()
        alert.messageText = "Join VirtualBuddy Beta"
        alert.informativeText = """
        Would like to join the beta and receive pre-release updates for testing?
        
        If you decide to stop receiving beta updates in the future, you will have to manually download and install the release version of VirtualBuddy.
        """
        alert.addButton(withTitle: "Join Beta")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        settings.updateChannel = .beta
    }
}

extension URL {
    func performWriteTest() -> String? {
        if !FileManager.default.fileExists(atPath: path) {
            return "The directory \(lastPathComponent) doesn't exist."
        }

        do {
            let testFileURL = appendingPathComponent(".vbtest-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: testFileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: testFileURL)
            return nil
        } catch {
            return "VirtualBuddy is unable to write files to the directory \(lastPathComponent). Please check the permissions for that directory or choose a different one."
        }
    }
}

#if DEBUG
#Preview("Library Settings") {
    SettingsScreen.preview(.general)
}
#endif
