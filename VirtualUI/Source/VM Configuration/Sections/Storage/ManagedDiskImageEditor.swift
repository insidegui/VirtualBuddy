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

    init(image: VBManagedDiskImage, isExistingDiskImage: Bool, isForBootVolume: Bool, onSave: @escaping (VBManagedDiskImage) -> Void) {
        self._image = .init(wrappedValue: image)
        self.isExistingDiskImage = isExistingDiskImage
        self.onSave = onSave
        let fallbackMinimumSize = isForBootVolume ? VBManagedDiskImage.minimumBootDiskImageSize : VBManagedDiskImage.minimumExtraDiskImageSize
        self.minimumSize = isExistingDiskImage ? image.size : fallbackMinimumSize
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
                }
            }
            .padding(.bottom)

            NumericPropertyControl(
                value: $image.size.gbStorageValue,
                range: minimumSize.gbStorageValue...VBManagedDiskImage.maximumExtraDiskImageSize.gbStorageValue,
                hideSlider: isExistingDiskImage,
                label: "Disk Image Size (GB)",
                formatter: NumberFormatter.numericPropertyControlDefault
            )
            .disabled(isExistingDiskImage)

            VStack(alignment: .leading, spacing: 8) {
                if !isExistingDiskImage {
                    Text("You'll have to use Disk Utility in the guest operating system to initialize the disk image. If you see an error after it boots up, choose the \"Initialize\" option.")
                        .foregroundColor(.yellow)
                }
                
                Text(sizeMessage)
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
    
    private var sizeMessage: String {
        if isExistingDiskImage {
            return "It's not possible to change the size of an existing storage device."
        } else {
            let prefix = VBSettingsContainer.current.isLibraryInAPFSVolume ? "The storage space you make available for the disk image won't be used immediately, only the space that's actually used by the virtual machine will be consumed. " : ""
            return "\(prefix)After adding the storage device, it won't be possible to change the size of its disk image with VirtualBuddy."
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
