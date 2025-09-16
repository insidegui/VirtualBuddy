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
    
    /// Checks if any disk images need resizing based on configuration vs actual size
    func checkAndResizeDiskImages() async throws {
        let config = configuration
        
        for device in config.hardware.storageDevices {
            guard case .managedImage(let image) = device.backing else { continue }
            guard image.canBeResized else { continue }
            
            let imageURL = diskImageURL(for: image)
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: imageURL.path) else { continue }
            
            // Get actual file size
            let attributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
            let actualSize = attributes[.size] as? UInt64 ?? 0
            
            // If configured size is larger than actual size, resize the disk
            if image.size > actualSize {
                try await resizeDiskImage(image, to: image.size)
            }
        }
    }
    
    /// Resizes a managed disk image to the specified size
    private func resizeDiskImage(_ image: VBManagedDiskImage, to newSize: UInt64) async throws {
        let imageURL = diskImageURL(for: image)
        NSLog("Resizing disk image at \(imageURL.path) from current size to \(newSize) bytes")
        
        try await VBDiskResizer.resizeDiskImage(
            at: imageURL,
            format: image.format,
            newSize: newSize
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
}
