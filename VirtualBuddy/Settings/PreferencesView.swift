//
//  PreferencesView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 05/06/22.
//

import SwiftUI
import VirtualCore

struct PreferencesView: View {

    @EnvironmentObject var container: VBSettingsContainer

    private var settings: VBSettings {
        get { container.settings }
        nonmutating set { container.settings = newValue }
    }

    var body: some View {
        DecentFormView {
            DecentFormControl {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Library Path:", text: libraryPathBinding)
                        .frame(minWidth: 200, maxWidth: 300)

                    Button("Choose…", action: showOpenPanel)
                }
            } label: {
                Text("Library Path:")
            }
        }
        .padding()
    }

    private var libraryPathBinding: Binding<String> {
        .init {
            settings.libraryURL.path
        } set: { newValue in
            #warning("TODO: Validate URL and show an error if it's invalid")
            settings.libraryURL = URL(fileURLWithPath: newValue)
        }
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = settings.libraryURL

        guard panel.runModal() == .OK,
                let url = panel.url,
                url != settings.libraryURL else { return }

        settings.libraryURL = url
    }

}
