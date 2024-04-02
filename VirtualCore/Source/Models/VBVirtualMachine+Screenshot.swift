import Cocoa

public extension VBVirtualMachine {

    var screenshot: NSImage? {
        guard let imageData = metadataContents(VBVirtualMachine.screenshotFileName) ?? metadataContents(VBVirtualMachine._legacyScreenshotFileName) else { return nil }
        return NSImage(data: imageData)
    }

    func thumbnailImage() -> NSImage? {
        guard let thumbnailURL = try? metadataFileURL(Self.thumbnailFileName) else { return nil }
        
        if let existingImage = NSImage(contentsOf: thumbnailURL) {
            return existingImage
        }
        
        return try? screenshot?.vb_createThumbnail(at: thumbnailURL)
    }

    func invalidateThumbnail() throws {
        try deleteMetadataFile(named: Self.thumbnailFileName)

        DispatchQueue.main.async {
            self.didInvalidateThumbnail.send()
        }
    }

}
