//
//  InstallConfigurationStepView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct InstallConfigurationStepView: View {
    @StateObject private var viewModel: VMConfigurationViewModel
    @State private var vm: VBVirtualMachine
    var onSave: (VBVirtualMachine) -> Void
    
    init(vm: VBVirtualMachine, onSave: @escaping (VBVirtualMachine) -> Void) {
        self._vm = .init(wrappedValue: vm)
        self._viewModel = .init(wrappedValue: VMConfigurationViewModel(vm, context: .preInstall))
        self.onSave = onSave
    }
    
    var body: some View {
        VMConfigurationSheet(configuration: $vm.configuration, customConfirmationButtonAction: { configuration in
            var updatedVM = vm
            updatedVM.configuration = configuration
            self.vm = updatedVM
            onSave(updatedVM)
        })
            .environmentObject(viewModel)
    }
}

#if DEBUG
struct VMInstallerConfigurationStepView_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }
    
    struct _Template: View {
        @State private var vm = VBVirtualMachine.preview

        var body: some View {
            InstallConfigurationStepView(vm: vm, onSave: { _ in })
        }
    }
}
#endif
