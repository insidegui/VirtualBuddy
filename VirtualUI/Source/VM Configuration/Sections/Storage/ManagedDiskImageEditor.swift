//
//  ManagedDiskImageEditor.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct ManagedDiskImageEditor: View {
    @State private var image: VBManagedDiskImage
    let virtualMachine: VBVirtualMachine
    var minimumSize: UInt64
    var isExistingDiskImage: Bool
    var onSave: (VBManagedDiskImage) -> Void
    var isBootVolume: Bool
    var canResize: Bool

    init(image: VBManagedDiskImage, virtualMachine: VBVirtualMachine, isExistingDiskImage: Bool, isForBootVolume: Bool, onSave: @escaping (VBManagedDiskImage) -> Void) {
        self._image = .init(wrappedValue: image)
        self.virtualMachine = virtualMachine
        self.isExistingDiskImage = isExistingDiskImage
        self.onSave = onSave
        let fallbackMinimumSize = isForBootVolume ? VBManagedDiskImage.minimumBootDiskImageSize : VBManagedDiskImage.minimumExtraDiskImageSize
        self.minimumSize = isExistingDiskImage ? image.size : fallbackMinimumSize
        self.isBootVolume = isForBootVolume
        self.canResize = isExistingDiskImage && image.canBeResized
    }

    private let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useTB]
        f.formattingContext = .standalone
        f.countStyle = .binary
        return f
    }()

    @State private var nameError: String?

    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject private var viewModel: VMConfigurationViewModel

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if let nameError {
                    Text(nameError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .padding(.bottom)
                }
            }

            HStack(alignment: .top) {
                NumericPropertyControl(
                    value: $image.size.gbStorageValue,
                    range: selectableSizeRangeInGigabytes,
                    step: 1,
                    hideSlider: isExistingDiskImage && !canResize,
                    label: isBootVolume ? "Boot Disk Size (GB)" : "Disk Image Size (GB)",
                    formatter: NumberFormatter.numericPropertyControlDefault
                )
                .disabled(isExistingDiskImage && !canResize)
                .foregroundColor(sizeWarning != nil ? .yellow : .primary)

                if isExistingDiskImage && canResize {
                    Stepper(
                        value: $image.size.gbStorageValue,
                        in: selectableSizeRangeInGigabytes,
                        step: 1
                    ) { EmptyView() }
                        .labelsHidden()
                        .disabled(!canIncreaseSize)
                        .help("Adjust disk size by 1 GB")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if isExistingDiskImage && canResize {
                    HStack(spacing: 8) {
                        Button("Use Maximum") {
                            image.size = maximumSelectableSize
                        }
                        .controlSize(.small)
                        .disabled(!canIncreaseSize || image.size == maximumSelectableSize)

                        if let storageLimitMessage {
                            Text(storageLimitMessage)
                        }
                    }
                }

                if !isExistingDiskImage, !isBootVolume {
                    Text("You'll have to use Disk Utility in the guest operating system to initialize the disk image. If you see an error after it boots up, choose the \"Initialize\" option.")
                        .foregroundColor(.yellow)
                }

                if isExistingDiskImage && canResize {
                    Text("This \(image.format.displayName) can be expanded. After resizing, you may need to expand the partition using Disk Utility in the guest operating system.")
                        .foregroundColor(.blue)
                }

                if let sizeWarning {
                    Text(sizeWarning)
                        .foregroundColor(.yellow)
                }

                if isBootVolume {
                    Text(sizeChangeInfo)
                        .foregroundColor(.yellow)

                    if let sizeMessagePrefix {
                        Text(sizeMessagePrefix)
                    }
                } else {
                    Text(sizeMessage)
                }
            }
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
        }
        .onChange(of: image) { _, newValue in
            viewModel.updateDiskImageResizeConfirmation(
                for: newValue,
                originalSize: minimumSize,
                deviceName: deviceName,
                isExistingDiskImage: isExistingDiskImage,
                canResize: canResize
            )
            onSave(newValue)
        }
        .onAppear {
            image.size = image.size.limited(to: selectableSizeRange)
        }
    }

    private var configuredMaximumSize: UInt64 {
        isBootVolume ? VBManagedDiskImage.maximumBootDiskImageSize : VBManagedDiskImage.maximumExtraDiskImageSize
    }

    private var maximumSelectableSize: UInt64 {
        let libraryURL = VBSettingsContainer.current.settings.libraryURL

        let rawMaximum = VBManagedDiskImage.maximumSelectableSize(
            configuredMaximum: configuredMaximumSize,
            minimumSize: minimumSize,
            existingImageSize: isExistingDiskImage ? minimumSize : nil,
            availableSpace: libraryURL.freeDiskSpaceOnVolume,
            volumeCapacity: libraryURL.totalDiskSpaceOnVolume
        )

        let gigabyteAlignedMaximum = UInt64(rawMaximum.gbStorageValue) * .storageGigabyte
        return max(minimumSize, gigabyteAlignedMaximum)
    }

    private var selectableSizeRange: ClosedRange<UInt64> {
        minimumSize...maximumSelectableSize
    }

    private var selectableSizeRangeInGigabytes: ClosedRange<Int> {
        minimumSize.gbStorageValue...maximumSelectableSize.gbStorageValue
    }

    private var canIncreaseSize: Bool {
        maximumSelectableSize > minimumSize
    }

    private var deviceName: String {
        isBootVolume ? "Boot" : image.filename
    }

    private var storageLimitMessage: String? {
        guard canResize else { return nil }
        guard let availableSpace = VBSettingsContainer.current.settings.libraryURL.freeDiskSpaceOnVolume else { return nil }

        let availableDescription = formatter.string(fromByteCount: Int64(availableSpace))
        let maximumDescription = formatter.string(fromByteCount: Int64(maximumSelectableSize))

        return "Up to \(maximumDescription), based on \(availableDescription) free on \(volumeDescription)."
    }

    private var sizeMessagePrefix: String? {
        VBSettingsContainer.current.isLibraryInAPFSVolume ? "The storage space you make available for the disk won't be used immediately, only the space that's used by the virtual machine will be consumed. " : nil
    }

    private var sizeChangeInfo: String {
        switch (isBootVolume, canResize) {
        case (true, true):
            "Boot disk can be expanded, but not shrunk. Choose your size carefully."
        case (true, false):
            "Be sure to reserve enough space, since it won't be possible to change the size of the disk later."
        case (false, true):
            "This disk can be expanded to a larger size, but cannot be shrunk."
        case (false, false):
            "It's not possible to change the size of an existing storage device."
        }
    }
    
    private var sizeMessage: String {
        if isExistingDiskImage {
            sizeChangeInfo
        } else {
            "\(sizeMessagePrefix ?? "")After adding the storage device, it won't be possible to change the size of its disk image with VirtualBuddy."
        }
    }

    private var sizeWarning: String? {
        guard !VBSettingsContainer.current.libraryVolumeCanFit(image.size) else { return nil }

        return "The volume \(volumeDescription) doesn't have enough free space to fit the full size of the disk image."
    }

    private var volumeDescription: String {
        if let volumeName = VBSettingsContainer.current.settings.libraryURL.containingVolumeName {
            return "\"\(volumeName)\""
        } else {
            return "where your library is stored"
        }
    }

}

#if DEBUG
struct ManagedDiskImageEditor_Previews: PreviewProvider {
    static var previews: some View {
        StorageDeviceDetailView_Previews.previews
    }
}
#endif
