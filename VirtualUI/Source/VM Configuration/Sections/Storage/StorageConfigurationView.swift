//
//  StorageConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct StorageConfigurationView: View {
    @EnvironmentObject var viewModel: VMConfigurationViewModel

    @Binding var hardware: VBMacDevice

    @State private var selection = Set<VBStorageDevice.ID>()

    @State private var isShowingDeviceConfigurationSheet = false
    @State private var deviceBeingConfigured: VBStorageDevice?

    var body: some View {
        GroupedList {
            List(selection: $selection) {
                ForEach($hardware.storageDevices) { $device in
                    StorageDeviceListItem(device: $device) {
                        configure(device)
                    }
                        .tag(device.id)
                }
            }
        } emptyOverlay: {
            EmptyView()
        } addButton: { label in
            Button {
                configure(.template)
            } label: {
                label
            }
            .help("Add storage device")
        } removeButton: { label in
            Button {
                for deviceID in selection {
                    guard let idx = hardware.storageDevices.firstIndex(where: { $0.id == deviceID }) else { continue }
                    guard !hardware.storageDevices[idx].isBootVolume else { continue }
                    hardware.storageDevices.remove(at: idx)
                }
            } label: {
                label
            }
            .disabled(selection.isEmpty)
            .help("Remove selected devices")
        }
        .sheet(isPresented: $isShowingDeviceConfigurationSheet) {
            let device = deviceBeingConfigured ?? .template
            StorageDeviceDetailView(device: device, isExistingDiskImage: device.diskImageExists(for: viewModel.vm), onSave: { updatedDevice in
                hardware.addOrUpdate(updatedDevice)
            })
            .padding()
            .frame(minWidth: 280, idealWidth: 340, maxWidth: .infinity)
        }
    }

    private func configure(_ device: VBStorageDevice) {
        deviceBeingConfigured = device
        isShowingDeviceConfigurationSheet = true
    }
}

struct StorageDeviceListItem: View {
    @Binding var device: VBStorageDevice
    var configureDevice: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Toggle(device.name, isOn: $device.isEnabled)
                .disabled(device.isBootVolume)
                .help(device.isBootVolume ? "The boot storage device can't be disabled" : "Enable/disable this storage device")

            label
        }
            .lineLimit(1)
            .truncationMode(.middle)
            .labelsHidden()
            .padding(6)
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 6) {
            device.iconView

            Text(device.name)
                .help(device.customDiskImageURL?.path ?? device.diskImageName)

            Spacer()

            Button {
                configureDevice()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Device settings")
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .opacity(device.isEnabled ? 1 : 0.8)

    }
}

extension VBStorageDevice {
    var icon: Image {
        if isUSBMassStorageDevice {
            return Image(systemName: "externaldrive.fill")
        } else if isBootVolume {
            return Image(systemName: "wrench.and.screwdriver.fill")
        } else {
            return Image(systemName: "internaldrive.fill")
        }
    }

    @ViewBuilder
    var iconView: some View {
        icon
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: 16)
        .symbolRenderingMode(.hierarchical)
    }
}

#if DEBUG
struct StorageConfigurationView_Previews: PreviewProvider {
    static var config: VBMacConfiguration {
        var c = VBMacConfiguration.default
        c.hardware.storageDevices.append(.init(name: "Custom", isBootVolume: false, isReadOnly: false, isUSBMassStorageDevice: false, diskImageName: "Custom.img", customDiskImageURL: URL(fileURLWithPath: "/Users/insidegui/Documents/Custom.img"), size: VBStorageDevice.defaultBootDiskImageSize))
        return c
    }
    static var previews: some View {
        _ConfigurationSectionPreview(config) { StorageConfigurationView(hardware: $0.hardware) }
            .environmentObject(VMConfigurationViewModel(.preview))
    }
}
#endif
