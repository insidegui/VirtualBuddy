//
//  VBVirtualMachine+DiskResize.swift
//  VirtualCore
//
//  Created by VirtualBuddy on 25/05/26.
//

import Foundation
import OSLog

private let diskResizeLogger = Logger(for: VBVirtualMachine.self, label: "DiskResize")

public extension VBVirtualMachine {

    typealias DiskResizeProgressHandler = @MainActor (_ message: String) -> Void

    /// Checks if any disk images need resizing based on configuration vs actual size
    mutating func checkAndResizeDiskImages(progressHandler: DiskResizeProgressHandler? = nil) async throws {
        let config = configuration

        guard metadata.hasPendingDiskImageResizes else { return }

        let pendingImageIDs = metadata.pendingDiskImageResizeIDs

        func report(_ message: String) async {
            guard let progressHandler else { return }
            await MainActor.run {
                progressHandler(message)
            }
        }

        let resizableDevices = config.hardware.storageDevices.compactMap { device -> (VBStorageDevice, VBManagedDiskImage)? in
            guard case .managedImage(let image) = device.backing else { return nil }
            guard pendingImageIDs.contains(image.id) else { return nil }
            guard image.canBeResized else { return nil }
            return (device, image)
        }

        guard !resizableDevices.isEmpty else {
            metadata.pendingDiskImageResizeIDs.removeAll()
            return
        }

        let formatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB, .useTB]
            formatter.countStyle = .binary
            formatter.includesUnit = true
            return formatter
        }()

        for (index, entry) in resizableDevices.enumerated() {
            let (device, image) = entry
            let position = index + 1
            let total = resizableDevices.count
            let deviceName = device.displayName

            await report("Checking \(deviceName) (\(position)/\(total))...")

            let imageURL = diskImageURL(for: image)

            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                await report("Skipping \(deviceName): disk image not found.")
                metadata.clearPendingDiskImageResize(for: image)
                continue
            }

            let actualSize = try await VBDiskResizer.currentImageSize(at: imageURL, format: image.format)

            if image.size > actualSize {
                let targetDescription = formatter.string(fromByteCount: Int64(image.size))
                await report("Expanding \(deviceName) to \(targetDescription) (\(position)/\(total))...")

                try await resizeDiskImage(image, to: image.size)

                await report("\(deviceName) expanded successfully.")
                metadata.clearPendingDiskImageResize(for: image)
            } else if image.size < actualSize {
                let actualDescription = formatter.string(fromByteCount: Int64(actualSize))
                await report("\(deviceName) exceeds the configured size (\(actualDescription)); no changes made.")
                metadata.clearPendingDiskImageResize(for: image)
            } else {
                let currentDescription = formatter.string(fromByteCount: Int64(actualSize))
                if VBDiskResizer.shouldReconcilePartitions(
                    configuredSize: image.size,
                    actualSize: actualSize,
                    format: image.format
                ) {
                    await report("Verifying \(deviceName) partition layout (\(position)/\(total))...")
                    try await VBDiskResizer.reconcilePartitions(at: imageURL, format: image.format)
                }
                await report("\(deviceName) already uses \(currentDescription).")
                metadata.clearPendingDiskImageResize(for: image)
            }
        }

        await report("Disk image checks complete.")
    }

    /// Resizes a managed disk image to the specified size
    private func resizeDiskImage(_ image: VBManagedDiskImage, to newSize: UInt64) async throws {
        let imageURL = diskImageURL(for: image)
        diskResizeLogger.debug("Resizing disk image at \(imageURL.path, privacy: .public) to \(newSize, privacy: .public) bytes")

        try await VBDiskResizer.resizeDiskImage(
            at: imageURL,
            format: image.format,
            newSize: newSize
        )

        diskResizeLogger.debug("Successfully resized disk image at \(imageURL.path, privacy: .public) to \(newSize, privacy: .public) bytes")
    }

    /// Checks if a managed disk image has FileVault (locked volumes) enabled.
    /// - Parameter image: The managed disk image to check.
    /// - Returns: `true` if the disk image has FileVault-protected (locked) volumes, `false` otherwise.
    func checkFileVaultForDiskImage(_ image: VBManagedDiskImage) async -> Bool {
        let imageURL = diskImageURL(for: image)
        return await VBDiskResizer.checkFileVaultStatus(at: imageURL, format: image.format)
    }
}
