//
//  VBVirtualMachine+DiskResize.swift
//  VirtualCore
//
//  Created by VirtualBuddy on 22/08/25.
//

import Foundation

extension VBVirtualMachine {
    
    /// Checks if any disk images need resizing based on configuration vs actual size
    public func checkAndResizeDiskImages() async throws {
        guard let config = configuration else { return }
        
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
        
        try await VBDiskResizer.resizeDiskImage(
            at: imageURL,
            format: image.format,
            newSize: newSize
        )
    }
    
    /// Validates that all disk images can be resized if needed
    public func validateDiskResizeCapability() -> [(device: VBStorageDevice, canResize: Bool)] {
        guard let config = configuration else { return [] }
        
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