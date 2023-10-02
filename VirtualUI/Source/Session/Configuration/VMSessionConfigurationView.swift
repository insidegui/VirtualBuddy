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
        VStack(alignment: .trailing) {
            Group {
                if showInstallDeviceOption {
                    HStack {
                        Text("Boot on install drive")
                        Toggle("Boot on install drive", isOn: $controller.options.bootOnInstallDevice)
                    }
                }
                if showRecoveryModeOption {
                    HStack {
                        Text("Boot in recovery mode")
                        Toggle("Boot in recovery mode", isOn: $controller.options.bootInRecoveryMode)
                    }
                }
                HStack {
                    Text("Capture system keyboard shortcuts")
                    Toggle("Capture system keyboard shortcuts", isOn: $controller.virtualMachineModel.configuration.captureSystemKeys)
                }
            }
            .labelsHidden()
            .controlSize(.mini)
            .font(.system(.body))

            Button("VM Settings…") {
                isShowingVMSettings.toggle()
            }
            .padding(.top)
        }
        .toggleStyle(.switch)
        .padding()
        .controlGroup()
        .sheet(isPresented: $isShowingVMSettings) {
            VMConfigurationSheet(
                configuration: $controller.virtualMachineModel.configuration
            )
            .environmentObject(VMConfigurationViewModel(vm))
        }
    }
    
    private var showInstallDeviceOption: Bool { vm.configuration.systemType == .linux && vm.metadata.installImageURL != nil }

    private var showRecoveryModeOption: Bool { vm.configuration.systemType == .mac }
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

#if DEBUG
struct VMSessionConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        VMSessionConfigurationView()
            .environmentObject(VMController(with: .preview))
            .padding()
    }
}
#endif
