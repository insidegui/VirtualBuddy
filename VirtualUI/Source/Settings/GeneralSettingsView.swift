//
//  GeneralSettingsView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/06/25.
//

import SwiftUI
import VirtualCore
import BuddyKit

struct GeneralSettingsView: View {
    @Binding var settings: VBSettings
    @Binding var enableAutomaticUpdates: Bool
    @Binding var alert: AlertContent

    @State private var libraryPathText = ""

    private var libraryPath: String { settings.libraryURL.absoluteURL.path(percentEncoded: false) }

    var body: some View {
        Form {
            Section {
                FileSystemPathFormControl(url: settings.libraryURL, contentTypes: [.folder], defaultDirectoryKey: "library") { newURL in
                    setLibraryPath(to: newURL.path)
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("VirtualBuddy saves your virtual machines and downloaded installer images here.")
                    .settingsFooterStyle()
            }

            Section {
                Toggle("Automatically check for updates", isOn: $enableAutomaticUpdates)

                betaSection
            } header: {
                Text("App Updates")
            }
        }
        .navigationTitle(Text("General"))
        .task(id: settings.libraryURL.path) {
            libraryPathText = settings.libraryURL.path
        }
    }

    private func setLibraryPath(to newValue: String) {
        let url = URL(fileURLWithPath: newValue)

        if let errorMessage = url.performWriteTest() {
            libraryPathText = settings.libraryURL.path

            alert = AlertContent(errorMessage)
        } else {
            settings.libraryURL = url
            libraryPathText = url.path

            alert = .init()
        }
    }

    @ViewBuilder
    private var betaSection: some View {
        LabeledContent("Beta Updates") {
            if settings.updateChannel == .beta {
                Button("Disable") {
                    confirmDisableBeta()
                }
            } else {
                Button("Join Beta") {
                    confirmJoinBeta()
                }
            }
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

struct LibraryPathError: LocalizedError {
    var errorDescription: String?

    init(_ msg: String) { self.errorDescription = msg }
}

#if DEBUG
#Preview("Library Settings") {
    SettingsScreen.preview(.general)
}
#endif
