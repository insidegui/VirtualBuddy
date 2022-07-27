//
//  NVRAMConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 22/07/22.
//

import SwiftUI
import VirtualCore

struct NVRAMConfigurationView: View {

    @Binding var device: VBMacDevice

    @State private var selection = Set<VBNVRAMVariable.ID>()

    var body: some View {
        GroupedList {
            List(selection: $selection) {
                ForEach($device.NVRAM) { $variable in
                    Text(variable.name)
                        .tag(variable.id)
                }
            }
        } emptyOverlay: {
            EmptyView()
        } addButton: { label in
            Button {
                addVariable()
            } label: {
                label
            }
            .help("Add variable")
        } removeButton: { label in
            Button {
                for variableID in selection {
                    guard let idx = device.NVRAM.firstIndex(where: { $0.id == variableID }) else { continue }
                    device.NVRAM.remove(at: idx)
                }
            } label: {
                label
            }
            .disabled(selection.isEmpty)
            .help("Remove selected variables")
        }
    }

    private func addVariable() {

    }

}

#if DEBUG
struct NVRAMConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview(.nvramEditorPreview) { NVRAMConfigurationView(device: $0.hardware) }
    }
}
#endif
