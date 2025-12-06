//
//  ManagedDiskImageEditor.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct ManagedDiskImageEditor: View {
    @EnvironmentObject var viewModel: VMConfigurationViewModel
    @State private var image: VBManagedDiskImage
    var minimumSize: UInt64
    var isExistingDiskImage: Bool
    var onSave: (VBManagedDiskImage) -> Void
    var isBootVolume: Bool
    var canResize: Bool

    init(image: VBManagedDiskImage, isExistingDiskImage: Bool, isForBootVolume: Bool, onSave: @escaping (VBManagedDiskImage) -> Void) {
        self._image = .init(wrappedValue: image)
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
    @State private var isResizing = false
    @State private var showResizeConfirmation = false
    @State private var showFileVaultError = false
    @State private var newSize: UInt64 = 0
    @State private var sliderTimer: Timer?

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

            HStack {
                NumericPropertyControl(
                    value: $image.size.gbStorageValue,
                    range: minimumSize.gbStorageValue...VBManagedDiskImage.maximumExtraDiskImageSize.gbStorageValue,
                    hideSlider: isExistingDiskImage && !canResize,
                    label: isBootVolume ? "Boot Disk Size (GB)" : "Disk Image Size (GB)",
                    formatter: NumberFormatter.numericPropertyControlDefault
                )
                .disabled((isExistingDiskImage && !canResize) || isResizing)
                .foregroundColor(sizeWarning != nil ? .yellow : .primary)
                
                if isResizing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
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
        .onChange(of: image) { newValue in
            if isExistingDiskImage && canResize && newValue.size != minimumSize {
                // Cancel any existing timer
                sliderTimer?.invalidate()
                
                // Set a timer to show confirmation after user stops sliding
                sliderTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                    newSize = newValue.size
                    showResizeConfirmation = true
                }
            } else {
                onSave(newValue)
            }
        }
        .alert("Resize Disk Image", isPresented: $showResizeConfirmation) {
            Button("Cancel", role: .cancel) {
                image.size = minimumSize
            }
            Button("Resize") {
                performResize()
            }
        } message: {
                Text("This will resize the disk image from \(formatter.string(fromByteCount: Int64(minimumSize))) to \(formatter.string(fromByteCount: Int64(newSize))). The resize will run automatically the next time the virtual machine starts and may take some time. This operation cannot be undone.")
        }
        .alert("FileVault Enabled", isPresented: $showFileVaultError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This disk has FileVault encryption enabled. To resize the disk, you must first disable FileVault in the guest operating system's System Settings, then restart the virtual machine before attempting to resize again.")
        }
    }

    private var sizeMessagePrefix: String? {
        VBSettingsContainer.current.isLibraryInAPFSVolume ? "The storage space you make available for the disk won't be used immediately, only the space that's used by the virtual machine will be consumed. " : nil
    }

    private var sizeChangeInfo: String {
        if isBootVolume {
            if canResize {
                return "Boot disk can be expanded, but not shrunk. Choose your size carefully."
            } else {
                return "Be sure to reserve enough space, since it won't be possible to change the size of the disk later."
            }
        } else {
            if canResize {
                return "This disk can be expanded to a larger size, but cannot be shrunk."
            } else {
                return "It's not possible to change the size of an existing storage device."
            }
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
    
    private func performResize() {
        isResizing = true

        Task {
            // Check for FileVault before proceeding with resize
            let hasFileVault = await viewModel.vm.checkFileVaultForDiskImage(image)

            await MainActor.run {
                if hasFileVault {
                    // Reset size and show FileVault error
                    image.size = minimumSize
                    isResizing = false
                    showFileVaultError = true
                } else {
                    // Proceed with resize
                    image.size = newSize
                    onSave(image)
                    isResizing = false
                }
            }

            // The actual resize will happen automatically when VM starts or restarts
            // due to the size mismatch detection in checkAndResizeDiskImages()
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
