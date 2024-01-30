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
	@State private var isShowingHeadlessHelp = false
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
				HStack {
					Text("Boot in headless mode")
					Button(action: {
						isShowingHeadlessHelp.toggle()
					}, label: {
						Image(systemName: "questionmark.circle")
					})
					.buttonStyle(.borderless)
					.popover(isPresented: $isShowingHeadlessHelp, content: {
						Text("In headless mode, the virtual machine starts without displaying the GUI window. This can be useful when accessing the virtual machine via screen sharing.")
							.frame(width: 200)
							.padding()
					})
					Toggle("Boot in headless mode", isOn: $controller.options.bootHeadless)
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
