//
//  VMSessionConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore

struct VMSessionConfigurationView: View {
    @EnvironmentObject var controller: VMController

    private var options: VMSessionOptions {
        get { controller.options }
        nonmutating set { controller.options = newValue }
    }

    var body: some View {
        Form {
            Toggle("Boot in recovery mode", isOn: $controller.options.bootInRecoveryMode)
            Toggle("Capture system keyboard shortcuts", isOn: $controller.options.captureSystemKeys)
            Toggle("Shared folder enable", isOn: $controller.options.sharedFolderMountable)
            Toggle("Shared folder read only", isOn: $controller.options.sharedFolderReadOnly)
            DecentFormControl {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: sharedFolderPathBinding)
                        .frame(minWidth: 200, maxWidth: 400)
                    Button("Choose…", action: showSharedFolderOpenPanel)
                }
            } label: {
                Text("Shared Folder:")
            }
        }
        .padding()
        .groupBackground()
    }

    private var sharedFolderPathBinding: Binding<String> {
        .init {
            options.sharedFolder.path
        } set: { newValue in
            #warning("TODO: Validate URL and show an error if it's invalid")
            options.sharedFolder = URL(fileURLWithPath: newValue)
        }
    }

    private func showSharedFolderOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = options.sharedFolder

        guard panel.runModal() == .OK,
                let url = panel.url,
                url != options.sharedFolder else { return }

        options.sharedFolder = url
    }


}

struct GroupBackgroundModifier: ViewModifier {
    
    let material: Material
    
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).foregroundStyle(material))
    }
    
}

extension View {
    func groupBackground(material: Material = .ultraThin) -> some View {
        modifier(GroupBackgroundModifier(material: material))
    }
}

struct VMSessionConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        VMSessionConfigurationView()
            .environmentObject(VMController(with: .preview))
            .padding()
    }
}
