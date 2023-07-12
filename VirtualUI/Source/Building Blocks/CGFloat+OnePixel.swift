import CoreGraphics

public extension CGFloat {
    
    static func onePixel(in view: NSView?) -> CGFloat {
        guard let screen = view?.window?.screen ?? NSScreen.main else { return 1 }

        return 1 / screen.backingScaleFactor
    }

    static var onePixel: CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return 1 / scale
    }
    
}
