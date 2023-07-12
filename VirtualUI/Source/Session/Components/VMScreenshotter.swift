import Cocoa
import Combine
import OSLog
import CoreImage

final class VMScreenshotter {

    private lazy var logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: String(describing: Self.self))

    typealias Subject = PassthroughSubject<Data, Never>

    let screenshotSubject: Subject

    private weak var view: NSView?
    private let interval: TimeInterval
    
    init(interval: TimeInterval, screenshotSubject: Subject) {
        assert(interval > 1, "The minimum interval is 1 second")
        
        self.interval = max(1, interval)
        self.screenshotSubject = screenshotSubject
    }
    
    private var timer: Timer?
    
    func activate(with view: NSView) {
        invalidate()
        
        self.view = view

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { [weak self] _ in
            self?.timerFired()
        })
    }
    
    func invalidate() {
        pendingCapture?.cancel()
        timer?.invalidate()
        timer = nil
        
        guard let previousScreenshotData else { return }

        self.screenshotSubject.send(previousScreenshotData)
    }
    
    private func timerFired() {
        capture()
    }
    
    // Used to restore to the second-to-last screenshot when the machine shuts down,
    // so as to avoid having the screenshots all be the same (the Dock moving down and no Menu Bar).
    private var previousScreenshotData: Data?
    
    private var pendingCapture: Task<(), Error>?
    
    func capture() {
        pendingCapture = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let shot = await MainActor.run {
                self.takeScreenshot()
            }

            guard let shot else { return }

            try Task.checkCancellation()
            
            guard let data = shot.tiffRepresentation(using: .ccittfax4, factor: 0.8) else { return }
            
            self.previousScreenshotData = data
            
            try Task.checkCancellation()
            
            await MainActor.run {
                self.screenshotSubject.send(data)
            }
        }
    }

    private lazy var context = CIContext()

    @MainActor
    private func takeScreenshot() -> NSImage? {
        guard let view, let rootLayer = view.layer else {
            logger.fault("Couldn't get view and/or root layer for screenshot")
            return nil
        }
        
//        This caused flickering in the view:
//        if let surface = rootLayer.sublayers?.first?.sublayers?.first?.contents as? IOSurface {
//            let ciImage = CIImage(ioSurface: surface)
//            let rect = CGRect(x: 0, y: 0, width: surface.width, height: surface.height)
//            guard let cgImage = context.createCGImage(ciImage, from: rect) else {
//                logger.error("Failed to create CG image from IOSurface")
//                return nil
//            }
//            let result = NSImage(cgImage: cgImage, size: rect.size)
//            return result
//        } else {
//            logger.warning("Couldn't get IOSurface for screenshot, falling back to root layer")

            return NSImage(size: view.bounds.size, flipped: false) { [weak rootLayer] rect in
                guard let rootLayer else { return false }
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

                rootLayer.render(in: ctx)

                return true
            }
//        }
    }

}

extension NSImage: @unchecked Sendable { }
