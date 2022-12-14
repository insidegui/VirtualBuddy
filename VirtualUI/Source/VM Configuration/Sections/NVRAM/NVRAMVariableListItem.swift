//
//  SharedFolderListItem.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct NVRAMVariableListItem: View {
    @Binding var variable: VBNVRAMVariable

    var body: some View {
        HStack(spacing: 2) {
            label
        }
            .lineLimit(1)
            .truncationMode(.middle)
            .controlSize(.mini)
            .labelsHidden()
            .padding(.vertical, 4)
            /// Easier to hit trailing edge buttons without hovering floating scroll bar.
            .padding(.trailing, 4)
    }

    @ViewBuilder
    private var label: some View {
        let name = Binding(
            get: { self.variable.name },
            set: { self.variable = VBNVRAMVariable(name: $0, value: variable.value) }
        )

        HStack(spacing: 4) {
            Image(systemName: "memorychip")

            EphemeralTextField(name, alignment: .leading) { name in
                Text(name)
            } editableContent: { name in
                TextField("", text: .init(get: { name.wrappedValue }, set: { name.wrappedValue = $0 }))
            }

            Spacer()

            EphemeralTextField($variable.value, alignment: .leading) { value in
                let isEmpty = value == nil || value == ""

                Text(isEmpty ? "(none)" : (value ?? "(none)"))
                    .opacity(isEmpty ? 0.50 : 1.0)
            } editableContent: { value in
                TextField("", text: .init(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0 }))
            }
        }
        .padding(.leading, 6)
        .font(.system(size: 11))
    }
}
