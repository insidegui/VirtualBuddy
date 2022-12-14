//
//  SharedFoldersManagementView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct NVRAMManagementView: View {

    @Binding var hardware: VBMacDevice
    @Binding var nvram: [VBNVRAMVariable]

    init(hardware: Binding<VBMacDevice>) {
      self._hardware = hardware
      self._nvram = hardware.NVRAM
    }
    
    @State private var isShowingError = false
    @State private var errorMessage = "Error"
    @State private var selection = Set<VBNVRAMVariable.ID>()
    @State private var selectionBeingRemoved: Set<VBNVRAMVariable.ID>?
    @State private var isShowingRemovalConfirmation = false
    @State private var isShowingHelpPopover = false

    var body: some View {
        GroupedList {
            List(selection: $selection) {
                ForEach($nvram) { $variable in
                    NVRAMVariableListItem(variable: $variable)
                        .tag(variable.id)
                }
            }
        } headerAccessory: {
            headerAccessory
        } footerAccessory: {
            EmptyView()
        } emptyOverlay: {
            emptyOverlay
        } addButton: { label in
            Button {
                addVariable()
            } label: {
                label
            }
            .help("Add variable")
        } removeButton: { label in
            Button {
                confirmRemoval()
            } label: {
                label
            }
            .help("Remove selection from variables")
            .disabled(selection.isEmpty)
        }
    }
    
    @ViewBuilder
    private var emptyOverlay: some View {
        if nvram.isEmpty {
            Text("This VM has no variables.")
            Button("Add variable") {
                addVariable()
            }
            .buttonStyle(.link)
        }
    }

    @State private var showTip = false
    
    @ViewBuilder
    private var headerAccessory: some View {
        HStack {
            Text("Variables")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func addVariable() {
        hardware.addNVRAMVariable()
    }

    private func confirmRemoval(for vars: Set<VBNVRAMVariable.ID>? = nil) {
        let targetVars = vars ?? selection

        guard !targetVars.isEmpty else { return }
        selectionBeingRemoved = targetVars
        isShowingRemovalConfirmation = true
    }

    private func remove(_ identifiers: Set<VBNVRAMVariable.ID>) {
        hardware.removeNVRAMVariables(with: identifiers)
    }

    private func removalConfirmationTitle(with selection: Set<VBNVRAMVariable.ID>) -> String {
        guard selection.count == 1, let singleID = selection.first, let variable = hardware.NVRAM.first(where: { $0.id == singleID }) else {
            return "Remove \(selection.count) Folders"
        }

        return "Remove \"\(variable.name)\""
    }

    private func removalConfirmationMessage(with selection: Set<VBNVRAMVariable.ID>) -> String {
        guard selection.count == 1, let singleID = selection.first, let variable = hardware.NVRAM.first(where: { $0.id == singleID }) else {
            return "Are you sure you'd like to remove \(selection.count) variables?"
        }

        return "Are you sure you'd like to remove \"\(variable.name)\" from NVRAM?"
    }
}

#if DEBUG
struct NVRAMManagementView_Previews: PreviewProvider {
    static var previews: some View {
        NVRAMConfigurationView_Previews.previews
    }
}
#endif
