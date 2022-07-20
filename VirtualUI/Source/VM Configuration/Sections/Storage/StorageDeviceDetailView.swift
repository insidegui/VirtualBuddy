//
//  StorageDeviceDetailView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct StorageDeviceDetailView: View {
    @EnvironmentObject var viewModel: VMConfigurationViewModel
    
    @State private var device: VBStorageDevice
    var onSave: (VBStorageDevice) -> Void

    init(device: VBStorageDevice, onSave: @escaping (VBStorageDevice) -> Void) {
        self._device = .init(wrappedValue: device)
        self.onSave = onSave
    }

    @State private var nameError: String?

    @Environment(\.dismiss)
    private var dismiss
    
    private var canEditName: Bool { device.usesManagedDiskImage }

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    device.iconView

                    EphemeralTextField(.constant(device.displayName), alignment: .leading) { name in
                        Text(name)
                    } editableContent: { binding in
                        TextField("", text: binding)
                    }
                    .disabled(!canEditName)
                }
                
                diskImageDetail
            }
            .padding(.bottom)

            VStack(alignment: .leading) {
                Toggle("External Device", isOn: $device.isUSBMassStorageDevice)
                    .disabled(!VBStorageDevice.hostSupportsUSBMassStorage)
                    .help(VBStorageDevice.hostSupportsUSBMassStorage ? "Exposes the disk image as an external USB mass storage device to the virtual machine OS" : "This feature requires macOS 13 or later")

                Toggle("Read Only", isOn: $device.isReadOnly)
            }
            .padding(.top)
            .disabled(device.isBootVolume)
            .help(device.isBootVolume ? "These options are not available for the boot device" : "")
            
            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Done") {
                    onSave(device)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
    }
    
    @ViewBuilder
    private var diskImageDetail: some View {
        switch device.backing {
        case .managedImage(let image):
            ManagedDiskImageEditor(
                image: image,
                isExistingDiskImage: device.diskImageExists(for: viewModel.vm),
                isForBootVolume: device.isBootVolume,
                onSave: updateImage
            )
        case .customImage(let url):
            customDiskImageURLView(with: url)
        }
    }
    
    @ViewBuilder
    private func customDiskImageURLView(with url: URL) -> some View {
        Text(url.path)
    }
    
    private func updateImage(with newImage: VBManagedDiskImage) {
        device.backing = .managedImage(newImage)
    }
}

extension VBStorageDevice {
    var usesManagedDiskImage: Bool {
        guard case .managedImage = backing else { return false }
        return true
    }
}

#if DEBUG
struct StorageDeviceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let config = StorageConfigurationView_Previews.config
        ForEach(config.hardware.storageDevices.indices, id: \.self) {
            preview(at: $0)
                .previewDisplayName(config.hardware.storageDevices[$0].displayName)
        }
    }
    
    @ViewBuilder
    static func preview(at index: Int) -> some View {
        let config = StorageConfigurationView_Previews.config
        _ConfigurationSectionPreview(config, ungrouped: true) {
            StorageDeviceDetailView(device: $0.wrappedValue.hardware.storageDevices[index], onSave: { _ in })
        }
        .frame(maxHeight: 400)
        .environmentObject(VMConfigurationViewModel(.preview))
    }
}
#endif
