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
        guard let imageData = metadataContents(VBVirtualMachine.screenshotFileName) else { return nil }
        return NSImage(data: imageData)
    }

    func thumbnailImage(maxSize: CGSize = .init(width: 640, height: 480)) -> NSImage? {
        if let existingData = metadataContents(Self.thumbnailFileName),
           let existingImage = NSImage(data: existingData)
        {
            return existingImage
        }
        
        guard let image = screenshot else { return nil }

        let rect = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: maxSize))

        let resizedImage = NSImage(size: rect.size, flipped: true) { rect in
            image.draw(in: rect)
            return true
        }

        guard let data = resizedImage.tiffRepresentation else { return nil }

        guard let imageRep = NSBitmapImageRep(data: data) else {
            assertionFailure("Couldn't create NSBitmapImageRep from screenshot data")
            return nil
        }

        guard let jpegData = imageRep.representation(using: .jpeg, properties: [:]) else {
            assertionFailure("Couldn't generate JPEG data from screenshot")
            return nil
        }

        do {
            try write(jpegData, forMetadataFileNamed: Self.thumbnailFileName)
        } catch {
            assertionFailure("Couldn't write thumbnail: \(error)")
            return nil
        }

        return NSImage(data: jpegData)
    }

    func invalidateThumbnail() throws {
        try deleteMetadataFile(named: Self.thumbnailFileName)

        didInvalidateThumbnail.send()
    }

}
