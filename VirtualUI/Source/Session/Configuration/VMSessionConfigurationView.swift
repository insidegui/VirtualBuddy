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

    var body: some View {
        SelfSizingGroupedForm(minHeight: 100) {
            if showSavedStatePicker {
                SavedStatePicker(selectedStateURL: $controller.options.stateRestorationPackageURL)
                    .environmentObject(controller.savedStatesController)
            }
            
            if showInstallDeviceOption {
                Toggle("Boot on install drive", isOn: $controller.options.bootOnInstallDevice)
            }
            
            if showRecoveryModeOption {
                Toggle("Boot in recovery mode", isOn: $controller.options.bootInRecoveryMode)
                    .disabled(controller.options.bootInDFUMode)
            }

            if showDFUOption {
                Toggle("Boot in DFU mode", isOn: $controller.options.bootInDFUMode)
                    .disabled(controller.options.bootInRecoveryMode)
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

    private var showDFUOption: Bool { VBMacConfiguration.appBuildAllowsDFUMode && vm.configuration.systemType == .mac }

    private var showSavedStatePicker: Bool { vm.configuration.systemType.supportsStateRestoration }
}

#if DEBUG
#Preview {
    VirtualMachineSessionViewPreview()
}
#endif
