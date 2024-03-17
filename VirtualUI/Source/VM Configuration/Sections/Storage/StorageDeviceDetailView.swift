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
    var onSave: (VBStorageDevice) async throws -> Void
    
    init(device: VBStorageDevice, isNewDevice: Bool, onSave: @escaping (VBStorageDevice) async throws -> Void) {
        self._device = .init(wrappedValue: device)
        self.isNewDevice = isNewDevice
        self._imageType = .init(wrappedValue: isNewDevice ? nil : device.usesManagedDiskImage ? .managed : .custom)
        self.onSave = onSave
    }
    
    @State private var isLoading = false
    
    private var canSave: Bool {
        guard !isLoading else { return false }
        
        if imageType == .managed {
            return device.managedImage != nil
        } else {
            return device.customImageURL != nil
        }
    }
    
    @State private var managedImage: VBManagedDiskImage?
    @State private var customImageURL: URL?

    private var isNewDevice: Bool

    @State private var nameError: String?

    @Environment(\.dismiss)
    private var dismiss
    
    private var canEditName: Bool { device.usesManagedDiskImage }

    var body: some View {
        VStack(alignment: .leading) {
            if isNewDevice {
                if imageType != nil {
                    detail
                } else {
                    imageTypePicker
                }
            } else {
                detail
            }
            
            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Done") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.top)
        }
    }
    
    private func save() {
        isLoading = true
        
        Task {
            do {
                try await onSave(device)
                
                dismiss()
            } catch {
                NSAlert(error: error).runModal()
            }
            
            isLoading = false
        }
    }
    
    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                device.iconView

                let nameBinding: Binding<String> = switch device.backing {
                case .managedImage(var image):
                    Binding<String>(
                        get: {image.filename},
                        set: {
                            image.filename = $0
                            updateImage(with: image, type: .name)
                        }
                    )
                default:
                    .constant(device.displayName)
                }

                EphemeralTextField(nameBinding, alignment: .leading) { name in
                    Text(name)
                } editableContent: { binding in
                    TextField("", text: binding)
                }
                .disabled(!(canEditName && !device.diskImageExists(for: viewModel.vm)))
            }
            
            diskImageDetail
        }
        .padding(.bottom)
        
        Spacer()

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("External Device", isOn: $device.isUSBMassStorageDevice)
                    .disabled(!VBStorageDevice.hostSupportsUSBMassStorage)
                
                Text(VBStorageDevice.hostSupportsUSBMassStorage ? "Exposes the disk image as an external USB mass storage device to the virtual machine." : "This feature requires macOS 13 or later.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Read Only", isOn: $device.isReadOnly)
                
                Text("Makes the storage device appear read-only to the virtual machine. This doesn't affect the disk image.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(device.isBootVolume)
        .help(device.isBootVolume ? "These options are not available for the boot device" : "")
    }
    
    @State private var imageType: ImageType?
    
    private enum ImageType: Int, Identifiable, CaseIterable {
        var id: RawValue { rawValue }
        
        case managed
        case custom
        
        var name: String {
            switch self {
            case .managed:
                return "VirtualBuddy Disk Image"
            case .custom:
                return "Custom Image File"
            }
        }
    }

    private enum ImageUpdateType {
        case name
        case size
    }

    @ViewBuilder
    private var imageTypePicker: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 32) {
                HStack {
                    device.iconView
                    
                    Text("New Storage Device")
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("How would you like to create this storage device?")
                        .padding(.bottom, 6)
                        .font(.headline)
                    
                    Button {
                        imageType = .managed
                        device.backing = .managedImage(.template)
                    } label: {
                        Label("Create a new disk image with VirtualBuddy", systemImage: "externaldrive.fill.badge.plus")
                    }

                    Button {
                        selectCustomImage()
                    } label: {
                        Label("Select an existing disk image file", systemImage: "folder.fill.badge.plus")
                    }
                }
                .buttonStyle(.link)
                .symbolRenderingMode(.hierarchical)
            }
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var diskImageDetail: some View {
        VStack(alignment: .leading) {
            switch device.backing {
            case .managedImage(let image):
                ManagedDiskImageEditor(
                    image: image,
                    isExistingDiskImage: device.diskImageExists(for: viewModel.vm),
                    isForBootVolume: device.isBootVolume,
                    onSave: { (image) in updateImage(with: image, type: .size) }
                )
            case .customImage(let url):
                customDiskImageURLView(with: url)
            }
        }
    }
    
    @ViewBuilder
    private func customDiskImageURLView(with url: URL) -> some View {
        PropertyControl("Custom Disk Image File:", spacing: 8) {
            HStack {
                Text(url.path)
                    .truncationMode(.middle)
                    .lineLimit(1)
                
                Button("Change…") {
                    selectCustomImage()
                }
                .controlSize(.small)
            }
        }
        .padding(.top)
    }
    
    private func selectCustomImage() {
        guard let url = NSOpenPanel.run(accepting: [.diskImage], defaultDirectoryKey: "storageCustomImage") else {
            return
        }
        
        device.backing = .customImage(url)
        imageType = .custom
    }

    private func updateImage(with imgParam: VBManagedDiskImage, type: ImageUpdateType) {
        var newImage: VBManagedDiskImage
        if device.managedImage == nil {
            device.backing = .managedImage(imgParam)
        } else {
            newImage = device.managedImage!
            switch type {
            case .name:
                newImage.filename = imgParam.filename
            case .size:
                newImage.size = imgParam.size
            }
            device.backing = .managedImage(newImage)
        }
    }

}

extension VBStorageDevice {
    var usesManagedDiskImage: Bool {
        guard case .managedImage = backing else { return false }
        return true
    }
    var usesCustomDiskImage: Bool {
        guard case .customImage = backing else { return false }
        return true
    }
    var managedImage: VBManagedDiskImage? {
        guard case .managedImage(let image) = backing else { return nil }
        return image
    }
    var customImageURL: URL? {
        guard case .customImage(let url) = backing else { return nil }
        return url
    }
}

#if DEBUG
struct StorageDeviceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let config = VBMacConfiguration.preview
        ForEach(config.hardware.storageDevices.indices, id: \.self) {
            preview(at: $0)
                .previewDisplayName(config.hardware.storageDevices[$0].displayName)
        }
    }
    
    @ViewBuilder
    static func preview(at index: Int) -> some View {
        _ConfigurationSectionPreview(ungrouped: true) {
            StorageDeviceDetailView(device: $0.wrappedValue.hardware.storageDevices[index],
                                    isNewDevice: $0.wrappedValue.hardware.storageDevices[index].displayName == "New Device", onSave: { _ in })
        }
        .frame(maxHeight: 400)
        .environmentObject(VMConfigurationViewModel(.preview))
    }
}
#endif
