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
            pointingDevice
            network
            sound
            sharing
        }
        .font(.system(size: 12))
    }

    private func summaryHeader<Accessory: View>(_ title: String, systemImage: String, summary: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) -> some View {
        HStack {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
            }
            accessory()

            Spacer()

            if let summary {
                Text(summary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    private func summaryHeader(_ title: String, systemImage: String, summary: String? = nil) -> some View {
        summaryHeader(title, systemImage: systemImage, summary: summary, accessory: { EmptyView() })
    }

    @ViewBuilder
    private var general: some View {
        ConfigurationSection {
            HardwareConfigurationView(device: $viewModel.config.hardware)
        } header: {
            summaryHeader(
                "General",
                systemImage: "memorychip",
                summary: viewModel.config.generalSummary
            )
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
            summaryHeader("Display", systemImage: "display", summary: viewModel.config.displaySummary) {
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
    private var pointingDevice: some View {
        ConfigurationSection {
            PointingDeviceConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            summaryHeader(
                "Pointing Device",
                systemImage: "cursorarrow",
                summary: viewModel.config.pointingDeviceSummary
            )
        }
    }
    
    @ViewBuilder
    private var network: some View {
        ConfigurationSection {
            NetworkConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            summaryHeader(
                "Network",
                systemImage: "network",
                summary: viewModel.config.networkSummary
            )
        }
    }

    @ViewBuilder
    private var sound: some View {
        ConfigurationSection {
            SoundConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            summaryHeader(
                "Sound",
                systemImage: viewModel.config.hardware.soundDevices.isEmpty ? "speaker.slash" : "speaker.3",
                summary: viewModel.config.soundSummary
            )
        }
    }

    @ViewBuilder
    private var sharing: some View {
        ConfigurationSection {
            SharingConfigurationView(configuration: $viewModel.config)
        } header: {
            summaryHeader(
                "Sharing",
                systemImage: "folder",
                summary: viewModel.config.sharingSummary
            )
        }
    }
}

#if DEBUG
struct VMConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }

    struct _Template: View {
        @StateObject var controller = VMController(with: .preview)

        var body: some View {
            PreviewSheet {
                VMConfigurationSheet(machine: controller.virtualMachineModel, configuration: $controller.virtualMachineModel.configuration)
                    .frame(width: 360, height: 600, alignment: .top)
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
