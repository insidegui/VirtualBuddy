//
//  PreferencesView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 05/06/22.
//

import SwiftUI
import VirtualCore

public struct PreferencesView: View {

    @EnvironmentObject var container: VBSettingsContainer

    private var settings: VBSettings {
        get { container.settings }
        nonmutating set { container.settings = newValue }
    }

    @State private var libraryPathText = ""

    public init() { }

    public var body: some View {
        DecentFormView {
            DecentFormControl {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Library Path:", text: $libraryPathText)
                        .onSubmit {
                            setLibraryPath(to: libraryPathText)
                        }
                        .frame(minWidth: 200, maxWidth: 300)

                    Button("Choose…", action: showOpenPanel)
                }
            } label: {
                Text("Library Path:")
            }
        }
        .padding()
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
