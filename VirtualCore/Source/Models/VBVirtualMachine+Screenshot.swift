import Cocoa

public extension VBVirtualMachine {

    var screenshot: NSImage? {
        guard let imageData = metadataContents(VBVirtualMachine.screenshotFileName) ?? metadataContents(VBVirtualMachine._legacyScreenshotFileName) else { return nil }
        return NSImage(data: imageData)
    }

    var thumbnail: NSImage? {
        guard let imageData = metadataContents(VBVirtualMachine.thumbnailFileName) ?? metadataContents(VBVirtualMachine._legacyThumbnailFileName) else { return nil }
        return NSImage(data: imageData)
    }

    func thumbnailImage() -> NSImage? {
        let thumbnailURL = metadataFileURL(Self.thumbnailFileName)
        
        if let existingImage = NSImage(contentsOf: thumbnailURL) {
            return existingImage
        }
        
        return try? screenshot?.vb_createThumbnail(at: thumbnailURL)
    }

    func invalidateScreenshot() throws {
        try deleteMetadataFile(named: Self.screenshotFileName)
    }

    func invalidateThumbnail() throws {
        try deleteMetadataFile(named: Self.thumbnailFileName)
    }

}
