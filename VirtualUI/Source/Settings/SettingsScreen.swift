//
//  PreferencesView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 05/06/22.
//

import SwiftUI
import VirtualCore
import DeepLinkSecurity

public struct SettingsScreen: View {
    @Binding private var enableAutomaticUpdates: Bool
    private var deepLinkSentinel: () -> DeepLinkSentinel

    public init(enableAutomaticUpdates: Binding<Bool>, deepLinkSentinel: @escaping @autoclosure () -> DeepLinkSentinel) {
        self._enableAutomaticUpdates = enableAutomaticUpdates
        self.deepLinkSentinel = deepLinkSentinel
    }

    public var body: some View {
        SettingsRootView(enableAutomaticUpdates: $enableAutomaticUpdates)
            .environmentObject(deepLinkSentinel())
    }
}

private struct SettingsRootView: View {
    @EnvironmentObject private var container: VBSettingsContainer
    @EnvironmentObject private var sentinel: DeepLinkSentinel
    @Binding private var enableAutomaticUpdates: Bool

    public init(enableAutomaticUpdates: Binding<Bool>) {
        self._enableAutomaticUpdates = enableAutomaticUpdates
    }

    @State private var libraryPathText = ""
    @State private var showingAutomationSecuritySheet = false
    @State private var isShowingErrorAlert = false
    @State private var errorMessage: String?

    private var settings: VBSettings {
        get { container.settings }
        nonmutating set { container.settings = newValue }
    }

    private func setLibraryPath(to newValue: String) {
        let url = URL(fileURLWithPath: newValue)

        if let errorMessage = url.performWriteTest() {
            libraryPathText = settings.libraryURL.path

            isShowingErrorAlert = true
            self.errorMessage = errorMessage
        } else {
            settings.libraryURL = url
            libraryPathText = url.path

            self.errorMessage = nil
        }
    }

    private func showOpenPanel() {
        guard let newURL = NSOpenPanel.run(accepting: [.folder], directoryURL: settings.libraryURL, defaultDirectoryKey: "library") else {
            return
        }

        guard newURL != settings.libraryURL else { return }

        setLibraryPath(to: newURL.path)
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    HStack {
                        TextField("", text: $libraryPathText)
                            .onSubmit {
                                setLibraryPath(to: libraryPathText)
                            }

                        Button {
                            showOpenPanel()
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Choose")
                    }
                        .labelsHidden()
                }
            } header: {
                Text("Library Storage")
            } footer: {
                Text("This is where VirtualBuddy will store your virtual machines and installer images downloaded within the app.")
                    .foregroundStyle(.secondary)
            }

            if #available(macOS 26, *) {
                Section {
                    Picker("Boot Image Format", selection: $container.settings.bootDiskImagesUseASIF) {
                        Text("Most Efficient")
                            .tag(true)
                        Text("Most Compatible")
                            .tag(false)
                    }
                } header: {
                    Text("Disk Images")
                } footer: {
                    Text("""
                    Choose the disk image format that will be used when creating new virtual machines.
                    
                    - Most Efficient: uses the new ASIF format, requires the host to be running macOS 26 or later.
                    - Most Compatible: uses a raw image format, compatible with all versions of macOS supported by VirtualBuddy.
                    """)
                }
            }

            Section {
                Toggle("Automatically check for updates", isOn: $enableAutomaticUpdates)

                betaSection
            } header: {
                Text("App Updates")
            }

            Section {
                Toggle("Check signing status before downloading macOS", isOn: $container.settings.enableTSSCheck)
            } header: {
                Text("Services")
            }

            Section {
                LabeledContent("Control which apps can automate VirtualBuddy") {
                    Button {
                        showingAutomationSecuritySheet = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Automation")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAutomationSecuritySheet) {
            automationSecuritySheet
        }
        .frame(minWidth: 440, maxWidth: 440, minHeight: 500, maxHeight: .infinity, alignment: .top)
        .alert("Error", isPresented: $isShowingErrorAlert, actions: {
            Button("OK") { isShowingErrorAlert = false }
        }, message: {
            Text(errorMessage ?? "")
        })
        .task(id: settings.libraryURL.path) {
            libraryPathText = settings.libraryURL.path
        }
    }

    @ViewBuilder
    private var automationSecuritySheet: some View {
        DeepLinkAuthManagementUI(sentinel: sentinel)
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

// MARK: - Previews

#if DEBUG
private extension VBSettingsContainer {
    static let preview: VBSettingsContainer = {
        VBSettingsContainer(with: UserDefaults())
    }()
}

@available(macOS 14.0, *)
#Preview("Settings") {
    SettingsScreen(enableAutomaticUpdates: .constant(true), deepLinkSentinel: .preview)
        .environmentObject(VBSettingsContainer.preview)
}
#endif
