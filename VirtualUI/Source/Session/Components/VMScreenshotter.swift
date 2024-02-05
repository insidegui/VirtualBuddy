import Cocoa
import Combine
import OSLog
import CoreImage
import AVFoundation

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

            let data = await MainActor.run {
                self.takeScreenshot()
            }

            guard let data else { return }

            try Task.checkCancellation()

            self.previousScreenshotData = data

            try Task.checkCancellation()
            
            await MainActor.run {
                self.screenshotSubject.send(data)
            }
        }
    }

    private lazy var context = CIContext()

    private let imageOptions: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.8,
        kCGImageDestinationImageMaxPixelSize: 2000
    ]

    @MainActor
    private func takeScreenshot() -> Data? {
        guard let view else { return nil }
        
        let bounds = view.bounds

        guard bounds.width > 0, bounds.height > 0 else { return nil }

        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }

        view.cacheDisplay(in: bounds, to: bitmapRep)

        guard let cgImage = bitmapRep.cgImage else { return nil }

        guard let cfData = CFDataCreateMutable(kCFAllocatorDefault, 350_000) else { return nil }
        guard let destination = CGImageDestinationCreateWithData(cfData, AVFileType.heic.rawValue as CFString, 1, nil) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, imageOptions as CFDictionary)
        CGImageDestinationFinalize(destination)

        return cfData as Data
    }

}

extension NSImage: @unchecked Sendable { }
