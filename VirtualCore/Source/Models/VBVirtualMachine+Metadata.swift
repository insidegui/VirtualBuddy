//
//  VBVirtualMachine+Metadata.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 24/06/22.
//

import Cocoa

public extension VBVirtualMachine {

    func metadataDirectoryCreatingIfNeeded() throws -> URL {
        try metadataDirectoryURL.creatingDirectoryIfNeeded()
    }

    func write(_ data: Data, forMetadataFileNamed name: String) throws {
        let baseURL = try metadataDirectoryCreatingIfNeeded()

        let fileURL = baseURL.appendingPathComponent(name)

        try data.write(to: fileURL, options: .atomic)
    }

    func deleteMetadataFile(named name: String) throws {
        let fileURL = metadataDirectoryURL.appendingPathComponent(name)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        try FileManager.default.removeItem(at: fileURL)
    }

    func metadataFileURL(_ fileName: String) -> URL {
        let fileURL = metadataDirectoryURL.appendingPathComponent(fileName)

        return fileURL
    }

    func metadataContents(_ fileName: String) -> Data? {
        let fileURL = metadataFileURL(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        return try? Data(contentsOf: fileURL)
    }

}

extension URL {
    func creatingDirectoryIfNeeded() throws -> Self {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        }
        return self
    }
}

extension URL {
    /// `true` if URL points to a file contained within a VirtualBuddy VM bundle metadata directory.
    var isVirtualBuddyDataDirectoryFile: Bool {
        deletingLastPathComponent().lastPathComponent == VBVirtualMachine.metadataDirectoryName
    }

    var virtualMachineBundleParent: URL? {
        var current = self
        while current.pathExtension != VBVirtualMachine.bundleExtension {
            current = current.deletingLastPathComponent()
            guard current.path != "/" else { return nil }
        }
        return current
    }
}

// MARK: - Disk Resize Support

public extension VBVirtualMachine {

    typealias DiskResizeProgressHandler = @MainActor (_ message: String) -> Void

    /// Checks if any disk images need resizing based on configuration vs actual size
    func checkAndResizeDiskImages(progressHandler: DiskResizeProgressHandler? = nil) async throws {
        let config = configuration

        func report(_ message: String) async {
            guard let progressHandler else { return }
            await MainActor.run {
                progressHandler(message)
            }
        }

        let resizableDevices = config.hardware.storageDevices.compactMap { device -> (VBStorageDevice, VBManagedDiskImage)? in
            guard case .managedImage(let image) = device.backing else { return nil }
            guard image.canBeResized else { return nil }
            return (device, image)
        }

        guard !resizableDevices.isEmpty else {
            await report("Disk images already match their configured sizes.")
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
                continue
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
            let actualSize = attributes[.size] as? UInt64 ?? 0

            if image.size > actualSize {
                let targetDescription = formatter.string(fromByteCount: Int64(image.size))
                await report("Expanding \(deviceName) to \(targetDescription) (\(position)/\(total))...")

                try await resizeDiskImage(image, to: image.size)

                await report("\(deviceName) expanded successfully.")
            } else if image.size < actualSize {
                let actualDescription = formatter.string(fromByteCount: Int64(actualSize))
                await report("\(deviceName) exceeds the configured size (\(actualDescription)); no changes made.")
            } else {
                let currentDescription = formatter.string(fromByteCount: Int64(actualSize))
                await report("\(deviceName) already uses \(currentDescription).")
            }
        }

        await report("Disk image checks complete.")
    }
    
    /// Resizes a managed disk image to the specified size
    private func resizeDiskImage(_ image: VBManagedDiskImage, to newSize: UInt64) async throws {
        let imageURL = diskImageURL(for: image)
        NSLog("Resizing disk image at \(imageURL.path) from current size to \(newSize) bytes")

        try await VBDiskResizer.resizeDiskImage(
            at: imageURL,
            format: image.format,
            newSize: newSize,
            guestType: configuration.systemType
        )

        NSLog("Successfully resized disk image at \(imageURL.path) to \(newSize) bytes")
    }
    
    /// Validates that all disk images can be resized if needed
    func validateDiskResizeCapability() -> [(device: VBStorageDevice, canResize: Bool)] {
        let config = configuration

        return config.hardware.storageDevices.compactMap { device in
            guard case .managedImage(let image) = device.backing else { return nil }

            let imageURL = diskImageURL(for: image)
            let exists = FileManager.default.fileExists(atPath: imageURL.path)

            if !exists {
                // New image, no resize needed
                return nil
            }

            return (device: device, canResize: image.canBeResized)
        }
    }

    /// Checks if a managed disk image has FileVault (locked volumes) enabled.
    /// - Parameter image: The managed disk image to check.
    /// - Returns: `true` if the disk image has FileVault-protected (locked) volumes, `false` otherwise.
    func checkFileVaultForDiskImage(_ image: VBManagedDiskImage) async -> Bool {
        let imageURL = diskImageURL(for: image)
        return await VBDiskResizer.checkFileVaultStatus(at: imageURL, format: image.format)
    }
}
