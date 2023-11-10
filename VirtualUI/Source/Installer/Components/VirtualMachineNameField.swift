//
//  VirtualMachineNameField.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 01/08/22.
//

import SwiftUI
import VirtualCore

struct VirtualMachineNameField: View {
    @Binding var name: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField("Virtual Mac Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isFocused)

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
        .onAppearOnce {
            DispatchQueue.main.async {
                self.isFocused = true
            }
        }
    }
}

