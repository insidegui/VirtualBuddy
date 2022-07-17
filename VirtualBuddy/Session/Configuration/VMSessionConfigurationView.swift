//
//  VMSessionConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore
import VirtualUI

struct VMSessionConfigurationView: View {
    @EnvironmentObject var controller: VMController

    @State private var isShowingVMSettings = false
    
    var body: some View {
        VStack(alignment: .trailing) {
            Group {
                HStack {
                    Text("Boot in recovery mode")
                    Toggle("Boot in recovery mode", isOn: $controller.options.bootInRecoveryMode)
                }
                HStack {
                    Text("Capture system keyboard shortcuts")
                    Toggle("Capture system keyboard shortcuts", isOn: $controller.options.captureSystemKeys)
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
            VStack(spacing: 22) {
                VMConfigurationView(
                    configuration: $controller.virtualMachineModel.configuration,
                    hardware: $controller.virtualMachineModel.configuration.hardware
                )

                Button("Done") { isShowingVMSettings = false }
                    .keyboardShortcut(.defaultAction)
                    .frame(maxWidth: .infinity, alignment: .bottomTrailing)
            }
            .frame(minWidth: 320, maxWidth: .infinity)
            .padding()
        }
    }
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

struct VMSessionConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        VMSessionConfigurationView()
            .environmentObject(VMController(with: .preview))
            .padding()
    }
}
