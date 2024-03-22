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
    
    private var canEditName: Bool {
        device.usesManagedDiskImage && !device.diskImageExists(for: viewModel.vm)
    }

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

                EphemeralTextField($device.nameBinding, alignment: .leading) { name in
                    Text(name)
                } editableContent: { binding in
                    TextField("", text: binding)
                }
                .disabled(!canEditName)
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
                    onSave: { device.update(with: $0, type: .size) }
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
    
    private func updateImage(with newImage: VBManagedDiskImage) {
        device.backing = .managedImage(newImage)
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

extension Binding where Value == VBStorageDevice {
    var nameBinding: Binding<String> {
        switch wrappedValue.backing {
        case .customImage:
            return .constant(wrappedValue.displayName)
        case .managedImage:
            return .init {
                wrappedValue.managedImage?.filename ?? ""
            } set: { newValue in
                guard var image = wrappedValue.managedImage else { return }
                image.filename = newValue
                wrappedValue.backing = .managedImage(image)
            }
        }
    }
}

enum VBStorageImageUpdate {
    case name
    case size
}

extension VBStorageDevice {
    mutating func update(with image: VBManagedDiskImage, type: VBStorageImageUpdate) {
        guard var managedImage else {
            backing = .managedImage(image)
            return
        }

        switch type {
        case .name:
            managedImage.filename = image.filename
        case .size:
            managedImage.size = image.size
        }
        backing = .managedImage(managedImage)
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
