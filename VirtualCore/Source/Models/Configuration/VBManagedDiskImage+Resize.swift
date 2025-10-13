//
//  VBManagedDiskImage+Resize.swift
//  VirtualCore
//
//  Created by VirtualBuddy on 22/08/25.
//

import Foundation

extension VBManagedDiskImage {
    
    public var canBeResized: Bool {
        VBDiskResizer.canResizeFormat(format)
    }
    
    public var displayName: String {
        format.displayName
    }
    
    public func resized(to newSize: UInt64) -> VBManagedDiskImage {
        var copy = self
        copy.size = newSize
        return copy
    }
    
    public mutating func resize(to newSize: UInt64, at container: any VBStorageDeviceContainer) async throws {
        guard canBeResized else {
            throw VBDiskResizeError.unsupportedImageFormat(format)
        }
        
        guard newSize > size else {
            throw VBDiskResizeError.cannotShrinkDisk
        }
        
        guard newSize <= Self.maximumExtraDiskImageSize else {
            throw VBDiskResizeError.invalidSize(newSize)
        }
        
        let imageURL = container.diskImageURL(for: self)
        
        try await VBDiskResizer.resizeDiskImage(
            at: imageURL,
            format: format,
            newSize: newSize
        )
        
        self.size = newSize
    }
    
}

extension VBManagedDiskImage.Format {
    
    public var displayName: String {
        switch self {
        case .raw:
            return "Raw Image"
        case .dmg:
            return "Disk Image (DMG)"
        case .sparse:
            return "Sparse Image"
        case .asif:
            return "Apple Silicon Image"
        }
    }
    
    public var supportsResize: Bool {
        VBDiskResizer.canResizeFormat(self)
    }
    
}

extension VBStorageDevice {
    
    public func canBeResized(in container: any VBStorageDeviceContainer) -> Bool {
        guard let managedImage = managedImage else { return false }
        guard managedImage.canBeResized else { return false }
        
        let imageURL = container.diskImageURL(for: self)
        return FileManager.default.fileExists(atPath: imageURL.path)
    }
    
    public func resizeDisk(to newSize: UInt64, in container: any VBStorageDeviceContainer) async throws {
        guard var managedImage = managedImage else {
            throw VBDiskResizeError.unsupportedImageFormat(.raw)
        }
        
        try await managedImage.resize(to: newSize, at: container)
        backing = .managedImage(managedImage)
    }
    
}