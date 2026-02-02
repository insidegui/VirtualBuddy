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
    var minimumSize: UInt64
    var isExistingDiskImage: Bool
    var onSave: (VBManagedDiskImage) -> Void
    var isBootVolume: Bool

    init(image: VBManagedDiskImage, isExistingDiskImage: Bool, isForBootVolume: Bool, onSave: @escaping (VBManagedDiskImage) -> Void) {
        self._image = .init(wrappedValue: image)
        self.isExistingDiskImage = isExistingDiskImage
        self.onSave = onSave
        let fallbackMinimumSize = isForBootVolume ? VBManagedDiskImage.minimumBootDiskImageSize : VBManagedDiskImage.minimumExtraDiskImageSize
        self.minimumSize = isExistingDiskImage ? image.size : fallbackMinimumSize
        self.isBootVolume = isForBootVolume
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

            let maximumSize = isBootVolume ? VBManagedDiskImage.maximumBootDiskImageSize : VBManagedDiskImage.maximumExtraDiskImageSize
            NumericPropertyControl(
                value: $image.size.gbStorageValue,
                range: minimumSize.gbStorageValue...maximumSize.gbStorageValue,
                hideSlider: isExistingDiskImage,
                label: isBootVolume ? "Boot Disk Size (GB)" : "Disk Image Size (GB)",
                formatter: NumberFormatter.numericPropertyControlDefault
            )
            .disabled(isExistingDiskImage)
            .foregroundColor(sizeWarning != nil ? .yellow : .primary)

            VStack(alignment: .leading, spacing: 8) {
                if !isExistingDiskImage, !isBootVolume {
                    Text("You'll have to use Disk Utility in the guest operating system to initialize the disk image. If you see an error after it boots up, choose the \"Initialize\" option.")
                        .foregroundColor(.yellow)
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
        .onChange(of: image) { newValue in
            onSave(newValue)
        }
    }

    private var sizeMessagePrefix: String? {
        VBSettingsContainer.current.isLibraryInAPFSVolume ? "The storage space you make available for the disk won't be used immediately, only the space that's used by the virtual machine will be consumed. " : nil
    }

    private var sizeChangeInfo: String {
        if isBootVolume {
            return "Be sure to reserve enough space, since it won't be possible to change the size of the disk later."
        } else {
            return "It's not possible to change the size of an existing storage device."
        }
    }
    
    private var sizeMessage: String {
        if isExistingDiskImage {
            return sizeChangeInfo
        } else {
            return "\(sizeMessagePrefix ?? "")After adding the storage device, it won't be possible to change the size of its disk image with VirtualBuddy."
        }
    }

    private var sizeWarning: String? {
        guard !VBSettingsContainer.current.libraryVolumeCanFit(image.size) else { return nil }
        let volumeDescription: String
        if let volumeName = VBSettingsContainer.current.settings.libraryURL.containingVolumeName {
            volumeDescription = "\"\(volumeName)\""
        } else {
            volumeDescription = "where your library is stored"
        }

        return "The volume \(volumeDescription) doesn't have enough free space to fit the full size of the disk image."
    }
}

#if DEBUG
struct ManagedDiskImageEditor_Previews: PreviewProvider {
    static var previews: some View {
        StorageDeviceDetailView_Previews.previews
    }
}
#endif
