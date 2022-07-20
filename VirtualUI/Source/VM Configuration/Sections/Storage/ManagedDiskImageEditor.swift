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
                label: "Disk Image Size (GB)",
                formatter: NumberFormatter.numericPropertyControlDefault)

            Group {
                if isExistingDiskImage {
                    Text("It's not possible to decrease the size of an existing storage device. Increasing the configured size will cause the disk image to be resized when you save the configuration for this virtual machine.")
                } else {
                    Text("An empty disk image with the specified size will be created when you save the configuration for this virtual machine. After the disk image has been created, it's no longer possible to reduce its size, only increase it.")
                }
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(nil)
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
