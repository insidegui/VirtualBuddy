//
//  StorageDeviceDetailView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct StorageDeviceDetailView: View {
    @State private var device: VBStorageDevice
    var onSave: (VBStorageDevice) -> Void

    init(device: VBStorageDevice, onSave: @escaping (VBStorageDevice) -> Void) {
        self._device = .init(wrappedValue: device)
        self.onSave = onSave
    }

    private let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useTB]
        f.formattingContext = .standalone
        f.countStyle = .file
        return f
    }()

    @State private var nameError: String?

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    device.iconView

                    EphemeralTextField($device.name, alignment: .leading) { name in
                        Text(name)
                    } editableContent: { binding in
                        TextField("", text: binding)
                    } validate: { newName in
                        if let error = VBStorageDevice.validationError(for: newName) {
                            nameError = error
                            return false
                        } else {
                            nameError = nil
                            return true
                        }
                    }
                }

                if let nameError {
                    Text(nameError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                }
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
            .padding(.vertical)
        }
    }
}

#if DEBUG
struct StorageDeviceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview(ungrouped: true) {
            StorageDeviceDetailView(device: $0.wrappedValue.hardware.storageDevices[0], onSave: { _ in })
        }
        .frame(maxHeight: 400)
    }
}
#endif
