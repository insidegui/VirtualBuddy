//
//  VBVirtualMachine+Screenshot.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 24/06/22.
//

import Cocoa
import AVFoundation

public extension VBVirtualMachine {

    var screenshot: NSImage? {
        guard let imageData = metadataContents(VBVirtualMachine.screenshotFileName) ?? metadataContents(VBVirtualMachine._legacyScreenshotFileName) else { return nil }
        return NSImage(data: imageData)
    }

    static let thumbnailProperties = [
        kCGImageDestinationLossyCompressionQuality: 0.7,
        kCGImageDestinationImageMaxPixelSize: 640
    ] as CFDictionary

    func thumbnailImage() -> NSImage? {
        guard let thumbnailURL = try? metadataFileURL(Self.thumbnailFileName) else { return nil }

        if let existingImage = NSImage(contentsOf: thumbnailURL) {
            return existingImage
        }
        
        guard let cgImage = screenshot?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        guard let destination = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, AVFileType.heic as CFString, 1, nil) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, Self.thumbnailProperties)
        CGImageDestinationFinalize(destination)

        return NSImage(contentsOf: thumbnailURL)
    }

    func invalidateThumbnail() throws {
        try deleteMetadataFile(named: Self.thumbnailFileName)

        DispatchQueue.main.async {
            self.didInvalidateThumbnail.send()
        }
    }

}
