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

    @State private var isShowingVMSettings = false

    private var vm: VBVirtualMachine { controller.virtualMachineModel }

    @State private var selectedSaveState: VBSavedStatePackage?

    var body: some View {
        SelfSizingGroupedForm(minHeight: 100) {
            if showSavedStatePicker {
                SavedStatePicker(selection: $selectedSaveState)
                    .environmentObject(controller.savedStatesController)
            }
            
            if showInstallDeviceOption {
                Toggle("Boot on install drive", isOn: $controller.options.bootOnInstallDevice)
            }
            
            if showRecoveryModeOption {
                Toggle("Boot in recovery mode", isOn: $controller.options.bootInRecoveryMode)
            }
            
            Toggle("Capture system keyboard shortcuts", isOn: $controller.virtualMachineModel.configuration.captureSystemKeys)

            Button("Virtual Machine Settings…") {
                isShowingVMSettings.toggle()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .sheet(isPresented: $isShowingVMSettings) {
            VMConfigurationSheet(
                configuration: $controller.virtualMachineModel.configuration
            )
            .environmentObject(VMConfigurationViewModel(vm))
        }
    }
    
    private var showInstallDeviceOption: Bool { vm.configuration.systemType == .linux && vm.metadata.installImageURL != nil }

    private var showRecoveryModeOption: Bool { vm.configuration.systemType == .mac }

    private var showSavedStatePicker: Bool { vm.configuration.systemType == .mac }
}

#if DEBUG
struct VMSessionConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        VMSessionConfigurationView()
            .environmentObject(VMController(with: .preview, library: .preview))
    }
}
#endif
