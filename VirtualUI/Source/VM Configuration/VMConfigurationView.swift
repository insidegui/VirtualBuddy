//
//  VMConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI
import VirtualCore

struct VMConfigurationView: View {
    @EnvironmentObject private var viewModel: VMConfigurationViewModel
    
    var initialConfiguration: VBMacConfiguration

    static var labelSpacing: CGFloat { 2 }

    @AppStorage("config.general.collapsed")
    private var generalCollapsed = true

    @AppStorage("config.storage.collapsed")
    private var storageCollapsed = true

    @AppStorage("config.display.collapsed")
    private var displayCollapsed = true
    
    @AppStorage("config.pointing.collapsed")
    private var pointingCollapsed = true
    
    @AppStorage("config.network.collapsed")
    private var networkCollapsed = true
    
    @AppStorage("config.sound.collapsed")
    private var soundCollapsed = true
    
    @AppStorage("config.sharing.collapsed")
    private var sharingCollapsed = true

    private var showBootDiskSection: Bool { viewModel.context == .preInstall }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showBootDiskSection {
                bootDisk
            }
            general
            storage
            display
            pointingDevice
            network
            sound
            sharing
                .frame(minWidth: 0, idealWidth: VMConfigurationSheet.defaultWidth)
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
        ConfigurationSection($generalCollapsed) {
            HardwareConfigurationView(device: $viewModel.config.hardware)
        } header: {
            summaryHeader(
                "General",
                systemImage: "memorychip",
                summary: viewModel.config.generalSummary
            )
        }
    }

    @ViewBuilder
    private var bootDisk: some View {
        ConfigurationSection(.constant(false), collapsingDisabled: true) {
            if let image = (try? viewModel.vm.bootDevice)?.managedImage {
                ManagedDiskImageEditor(image: image, isExistingDiskImage: false, isForBootVolume: true) { image in
                    viewModel.updateBootStorageDevice(with: image)
                }
            } else {
                Text("Something went terribly wrong: VM doesn't have a boot storage device with a managed disk image.")
                    .foregroundColor(.red)
            }
        } header: {
            summaryHeader(
                "Boot Disk",
                systemImage: "wrench.and.screwdriver"
            )
        }
    }

    private var storageSummary: String {
        if showBootDiskSection {
            return viewModel.config.hardware.storageDevices.count == 1 ? "None" : viewModel.config.storageSummary
        } else {
            return viewModel.config.storageSummary
        }
    }

    @ViewBuilder
    private var storage: some View {
        ConfigurationSection($storageCollapsed) {
            StorageConfigurationView(hardware: $viewModel.config.hardware)
                .environmentObject(viewModel)
        } header: {
            summaryHeader(
                showBootDiskSection ? "Additional Storage" : "Storage",
                systemImage: "externaldrive",
                summary: storageSummary
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
        ConfigurationSection($displayCollapsed) {
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
        ConfigurationSection($pointingCollapsed) {
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
        ConfigurationSection($networkCollapsed) {
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
        ConfigurationSection($soundCollapsed) {
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
        ConfigurationSection($sharingCollapsed) {
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
        VMConfigurationSheet_Previews.previews
    }
}
#endif
