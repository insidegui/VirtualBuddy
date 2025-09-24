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

    private var hideBootDisk: Bool { viewModel.context == .preInstall }

    private func shouldHide(_ device: VBStorageDevice) -> Bool {
        if hideBootDisk {
            return device.isBootVolume
        } else {
            return false
        }
    }

    var body: some View {
        GroupedList {
            List(selection: $selection) {
                ForEach($hardware.storageDevices.filter({ !shouldHide($0.wrappedValue) })) { $device in
                    StorageDeviceListItem(device: $device) {
                        configure(device)
                    }
                        .tag(device.id)
                        .contextMenu {
                            if device.canBeResized {
                                Button("Resize Disk…") {
                                    configure(device)
                                }
                            }
                            
                            if !device.isBootVolume {
                                Button("Remove Device", role: .destructive) {
                                    if let idx = hardware.storageDevices.firstIndex(where: { $0.id == device.id }) {
                                        hardware.storageDevices.remove(at: idx)
                                    }
                                }
                            }
                        }
                }
            }
        } emptyOverlay: {
            EmptyView()
        } addButton: { label in
            Button {
                create()
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
            let isNewDevice = deviceBeingConfigured == nil

            StorageDeviceDetailView(device: device, isNewDevice: isNewDevice, onSave: { updatedDevice in
                if isNewDevice {
                    try await createImageIfNeeded(for: updatedDevice)
                }
                
                hardware.addOrUpdate(updatedDevice)
            })
            .environmentObject(viewModel)
            .padding()
            .frame(minWidth: 280, idealWidth: 340, maxWidth: .infinity)
        }
    }

    private func configure(_ device: VBStorageDevice?) {
        deviceBeingConfigured = device
        isShowingDeviceConfigurationSheet = true
    }
    
    private func create() {
        configure(nil)
    }
    
    private func createImageIfNeeded(for newDevice: VBStorageDevice) async throws {
        guard newDevice.usesManagedDiskImage else { return }
        
        try await viewModel.createImage(for: newDevice)
    }
}

struct StorageDeviceListItem: View {
    @EnvironmentObject var viewModel: VMConfigurationViewModel
    @Binding var device: VBStorageDevice
    var configureDevice: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Toggle(device.displayName, isOn: $device.isEnabled)
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

            Text(device.displayName)

            Spacer()
            
            if device.canBeResized {
                Image(systemName: "arrow.up.right.and.arrow.down.left")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .help("This disk can be resized")
            }

            Button {
                configureDevice()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Device settings")
            .buttonStyle(.plain)
            .disabled(device.isBootVolume)
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
    static var previews: some View {
        _ConfigurationSectionPreview { StorageConfigurationView(hardware: $0.hardware) }
            .environmentObject(VMConfigurationViewModel(.preview))
    }
}
#endif
