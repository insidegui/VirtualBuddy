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

    @State private var isCopyingDiskImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            list

            if viewModel.context == .postInstall, viewModel.hasExternalDiskImages {
                externalDiskImagesNotice
            }
        }
    }

    @ViewBuilder
    private var externalDiskImagesNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Some disk images are stored outside of this virtual machine. Its session can’t be saved until they’re copied into it. The originals are not changed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                copyExternalDiskImages()
            } label: {
                if isCopyingDiskImages {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Copy into Virtual Machine…")
                }
            }
            .disabled(isCopyingDiskImages)
        }
    }

    private func copyExternalDiskImages() {
        Task { @MainActor in
            let confirmed = await NSAlert.runConfirmationAlert(
                title: "Copy Disk Images Into the Virtual Machine?",
                message: "The disk images stored outside of this virtual machine are copied into it. The originals are not changed, and nothing is modified if copying fails. This can take a while and use a lot of disk space on volumes that don’t support cloning.",
                continueButtonTitle: "Copy",
                cancelButtonTitle: "Cancel"
            )
            guard confirmed else { return }

            isCopyingDiskImages = true
            defer { isCopyingDiskImages = false }

            do {
                try await viewModel.copyExternalDiskImagesIntoVirtualMachine()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private var list: some View {
        GroupedList {
            List(selection: $selection) {
                ForEach($hardware.storageDevices.filter({ !shouldHide($0.wrappedValue) })) { $device in
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
                create()
            } label: {
                label.groupedListButtonLabel()
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
                label.groupedListButtonLabel()
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

            Button {
                configureDevice()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("Device settings")
            .buttonStyle(.plain)
            .disabled(device.isBootVolume && !device.canBeResized)
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
