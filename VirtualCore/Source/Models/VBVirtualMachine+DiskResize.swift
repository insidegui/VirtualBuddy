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

    /// Expands managed disk images whose configured size is larger than the image on disk.
    /// Returns `true` if any disk image was expanded.
    @discardableResult
    func checkAndResizeDiskImages(progressHandler: DiskResizeProgressHandler? = nil) async throws -> Bool {
        let resizableImages = configuration.hardware.storageDevices.compactMap { device -> (name: String, image: VBManagedDiskImage)? in
            guard case .managedImage(let image) = device.backing, image.canBeResized else { return nil }
            return (device.displayName, image)
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.countStyle = .binary

        var didResize = false

        for (name, image) in resizableImages {
            let imageURL = diskImageURL(for: image)

            guard FileManager.default.fileExists(atPath: imageURL.path) else { continue }

            let actualSize = try await VBDiskResizer.currentImageSize(at: imageURL, format: image.format)
            guard image.size > actualSize else { continue }

            let targetDescription = formatter.string(fromByteCount: Int64(image.size))
            if let progressHandler {
                await progressHandler("Expanding \(name) to \(targetDescription)...")
            }

            diskResizeLogger.debug("Resizing disk image at \(imageURL.path, privacy: .public) to \(image.size, privacy: .public) bytes")
            try await VBDiskResizer.resizeDiskImage(at: imageURL, format: image.format, newSize: image.size)

            didResize = true
        }

        return didResize
    }
}
