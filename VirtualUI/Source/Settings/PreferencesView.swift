//
//  PreferencesView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 05/06/22.
//

import SwiftUI
import VirtualCore

/// This is a shell that handles showing the correct version depending on the OS and setting the library path,
/// which is the only preference in common between legacy OS (Monterey) and modern OSes (Ventura and later).
public struct PreferencesView: View {
    public init() { }
    
    @EnvironmentObject var container: VBSettingsContainer

    private var settings: VBSettings {
        get { container.settings }
        nonmutating set { container.settings = newValue }
    }

    @State private var libraryPathText = ""

    public var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                ModernSettingsView(libraryPathText: $libraryPathText, setLibraryPath: setLibraryPath, showOpenPanel: showOpenPanel)
            } else {
                LegacyPreferencesView(libraryPathText: $libraryPathText, setLibraryPath: setLibraryPath, showOpenPanel: showOpenPanel)
            }
        }
        .alert("Error", isPresented: $isShowingErrorAlert, actions: {
            Button("OK") { isShowingErrorAlert = false }
        }, message: {
            Text(errorMessage ?? "")
        })
        .onChange(of: settings.libraryURL) { newValue in
            libraryPathText = newValue.path
        }
        .onAppearOnce {
            libraryPathText = settings.libraryURL.path
        }
    }

    @State private var isShowingErrorAlert = false
    @State private var errorMessage: String?

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
        guard let newURL = NSOpenPanel.run(accepting: [.folder], directoryURL: settings.libraryURL) else {
            return
        }

        guard newURL != settings.libraryURL else { return }

        setLibraryPath(to: newURL.path)
    }
}

/// Settings view for modern OSes (Ventura and later).
@available(macOS 13.0, *)
private struct ModernSettingsView: View {
    @Binding var libraryPathText: String
    var setLibraryPath: (String) -> Void
    var showOpenPanel: () -> Void

    @EnvironmentObject var container: VBSettingsContainer

    private var settings: VBSettings {
        get { container.settings }
        nonmutating set { container.settings = newValue }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    HStack {
                        TextField("", text: $libraryPathText)
                            .onSubmit {
                                setLibraryPath(libraryPathText)
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
        }
        .formStyle(.grouped)
    }

    
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
    PreferencesView()
        .environmentObject(VBSettingsContainer.preview)
}
#endif











// MARK: - Legacy Preferences UI (macOS Monterey)

/// Settings view for macOS Monterey.
/// Should not be getting any new features since Monterey support is in maintenance mode.
private struct LegacyPreferencesView: View {

    @EnvironmentObject var container: VBSettingsContainer

    private var settings: VBSettings {
        get { container.settings }
        nonmutating set { container.settings = newValue }
    }

    @Binding var libraryPathText: String
    var setLibraryPath: (String) -> Void
    var showOpenPanel: () -> Void

    var body: some View {
        DecentFormView {
            DecentFormControl {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Library Path:", text: $libraryPathText)
                        .onSubmit {
                            setLibraryPath(libraryPathText)
                        }
                        .frame(minWidth: 200, maxWidth: 300)

                    Button("Choose…", action: showOpenPanel)
                }
            } label: {
                Text("Library Path:")
            }
        }
        .padding()
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
