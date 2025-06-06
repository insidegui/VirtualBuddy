//
//  VirtualMachineNameInputView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 01/08/22.
//

import SwiftUI
import VirtualCore

struct VirtualMachineNameInputView: View {
    @Binding var name: String

    var body: some View {
        VirtualBuddyInstallerInputView {
            HStack {
                TextField("Virtual Machine Name", text: $name)

                Spacer()

                Button {
                    name = RandomNameGenerator.shared.newName()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .help("Generate new name")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .keyboardShortcut(.init("r", modifiers: .command))
            }
        }
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .name)
}
#endif // DEBUG
