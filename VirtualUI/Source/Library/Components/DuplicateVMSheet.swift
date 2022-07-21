//
//  DuplicateVMSheet.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 21/07/22.
//

import SwiftUI
import VirtualCore

struct DuplicateVMSheet: View {

    typealias Method = VBVirtualMachine.DuplicationMethod

    var vm: VBVirtualMachine

    @State private var method = Method.changeID

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text("Duplicate “\(vm.name)”")
                    .font(.system(size: 22, weight: .medium, design: .rounded))

                Text("How would you like to duplicate this virtual machine?")
                    .font(.system(size: 15, weight: .medium))
            }

            Spacer()

            Picker("Duplicate Method", selection: $method) {
                ForEach(Method.allCases) { method in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(method.title)
                        Text(method.explainer)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 6)
                    }
                        .tag(method)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Duplicate") {
                    do {
                        try VMLibraryController.shared.duplicate(vm, using: method)
                        dismiss()
                    } catch {
                        NSAlert(error: error).runModal()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 460, maxHeight: 400)
        .padding(22)
    }

}

public extension VBVirtualMachine.DuplicationMethod {

    var title: String {
        switch self {
        case .clone:
            return "Make an exact clone"
        case .changeID:
            return "Change hardware identifiers"
        }
    }

    var explainer: String {
        switch self {
        case .clone:
            return "Copy the virtual machine as-is, including all hardware identifiers. You won't be able to have both copies booted at the same time."
        case .changeID:
            return "Copy the installed operating system, files, and settings, but change hardware identifiers. You'll be able to have both copies running simultaneously."
        }
    }

}

#if DEBUG
struct DuplicateVMSheet_Previews: PreviewProvider {
    static var previews: some View {
        DuplicateVMSheet(vm: .preview)
            .frame(maxWidth: 500, maxHeight: 400)
    }
}
#endif
