//
//  VMConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI
import VirtualCore

struct VMConfigurationView: View {
    @EnvironmentObject var controller: VMController
    @EnvironmentObject private var viewModel: VMConfigurationViewModel
    
    var initialConfiguration: VBMacConfiguration

    static var labelSpacing: CGFloat { 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            general
            display
            network
            sound
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private var general: some View {
        ConfigurationSection {
            HardwareConfigurationView(device: $viewModel.config.hardware)
        } header: {
            Label("General", systemImage: "memorychip")
        }
        .contextMenu {
            Button("Reset General Settings") {
                viewModel.config.hardware.cpuCount = initialConfiguration.hardware.cpuCount
                viewModel.config.hardware.memorySize = initialConfiguration.hardware.memorySize
            }
        }
    }

    @ViewBuilder
    private var display: some View {
        ConfigurationSection {
            DisplayConfigurationView(
                device: $viewModel.config.hardware.displayDevices[0],
                selectedPreset: $viewModel.selectedDisplayPreset
            )
        } header: {
            HStack {
                Label("Display", systemImage: "display")
                
                DisplayConfigurationView(
                    device: $viewModel.config.hardware.displayDevices[0],
                    selectedPreset: $viewModel.selectedDisplayPreset
                )
                .presetPicker
                .frame(width: 24)
            }
        }
    }
    
    @ViewBuilder
    private var network: some View {
        ConfigurationSection {
            NetworkConfigurationView(device: $viewModel.config.hardware.networkDevices[0])
        } header: {
            Label("Network", systemImage: "network")
        }
    }

    @ViewBuilder
    private var sound: some View {
        ConfigurationSection {
            SoundConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            Label("Sound", systemImage: "speaker.3")
        }

    }
}

#if DEBUG
struct VMConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
            .previewDisplayName("Sheet")
        
        _Template(error: "The virtual machine is not valid because something, or whatever.")
            .previewDisplayName("Error")
    }

    struct _Template: View {
        @StateObject var controller = VMController(with: .preview)
        
        var error: String? = nil

        var body: some View {
            PreviewSheet {
                VMConfigurationSheet(machine: controller.virtualMachineModel, configuration: $controller.virtualMachineModel.configuration, errorMessage: error, buttonsDisabled: error != nil)
                    .frame(width: 320, height: 600, alignment: .top)
            }
        }
    }
}

/// Simulates a macOS sheet for SwiftUI previews.
struct PreviewSheet<Content: View>: View {
    var content: () -> Content
    
    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        ZStack {}
        .frame(width: 500, height: 700)
        .background(Color.black.opacity(0.5))
        .overlay {
            content()
                .controlGroup()
        }
    }
}
#endif
