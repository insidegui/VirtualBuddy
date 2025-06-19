import Cocoa
import struct AVFoundation.AVFileType

public extension NSImage {
    static let defaultThumbnailProperties = [
        kCGImageDestinationLossyCompressionQuality: 0.9,
        kCGImageDestinationImageMaxPixelSize: 1024
    ] as CFDictionary

    static let defaultHEICProperties = [
        kCGImageDestinationLossyCompressionQuality: 1,
        kCGImageDestinationImageMaxPixelSize: 4096
    ] as CFDictionary

    // TODO: Adopt BuddyImageKit
    @discardableResult
    func vb_createThumbnail(at url: URL, options: CFDictionary = NSImage.defaultThumbnailProperties) throws -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure("Failed to create a CGImage")
        }

        try cgImage.vb_encodeHEIC(to: url, options: options)

        guard let thumbnailImage = NSImage(contentsOf: url) else {
            throw Failure("Failed to load generated thumbnail")
        }

        return thumbnailImage
    }

    // TODO: Adopt BuddyImageKit
    func vb_heicEncodedData(options: CFDictionary = NSImage.defaultHEICProperties) throws -> Data {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure("Failed to create a CGImage")
        }

        return try cgImage.vb_heicEncodedData(options: options)
    }

    // TODO: Adopt BuddyImageKit
    @discardableResult
    func vb_encodeHEIC(to url: URL, options: CFDictionary = NSImage.defaultHEICProperties) throws -> URL {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure("Failed to create a CGImage")
        }

        return try cgImage.vb_encodeHEIC(to: url, options: options)
    }
}

public extension CGImage {
    // TODO: Adopt BuddyImageKit
    func vb_heicEncodedData(options: CFDictionary = NSImage.defaultHEICProperties) throws -> Data {
        guard let cfData = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
            throw Failure("Failed to create CFMutableData")
        }
        guard let destination = CGImageDestinationCreateWithData(cfData, AVFileType.heic.rawValue as CFString, 1, nil) else {
            throw Failure("Failed to create image destination")
        }

        CGImageDestinationAddImage(destination, self, options)
        CGImageDestinationFinalize(destination)

        return cfData as Data
    }

    // TODO: Adopt BuddyImageKit
    @discardableResult
    func vb_encodeHEIC(to url: URL, options: CFDictionary = NSImage.defaultHEICProperties) throws -> URL {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, AVFileType.heic.rawValue as CFString, 1, nil) else {
            throw Failure("Failed to create image destination")
        }

        CGImageDestinationAddImage(destination, self, options)
        CGImageDestinationFinalize(destination)

        return url
    }
}
