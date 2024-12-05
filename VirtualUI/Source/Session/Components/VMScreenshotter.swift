import Cocoa
import Combine
import OSLog
import CoreImage
import VirtualCore

final class VMScreenshotter {

    private lazy var logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: String(describing: Self.self))

    typealias Subject = PassthroughSubject<Data, Never>

    let screenshotSubject: Subject

    private weak var view: NSView?
    private weak var vm: VZVirtualMachine?
    private var timingController: VMScreenshotTimingController!

    init(interval: TimeInterval, screenshotSubject: Subject) {
        self.screenshotSubject = screenshotSubject
        self.timingController = VMScreenshotTimingController(interval: interval) { [weak self] in
            guard let self else { return }
            try await self.capture()
        }
    }
    
    func activate(with view: NSView, vm: VZVirtualMachine?) {
        invalidate()
        
        self.view = view
        self.vm = vm
        
        timingController.activate()
    }
    
    func invalidate() {
        timingController.invalidate()

        guard let previousScreenshotData else { return }

        self.screenshotSubject.send(previousScreenshotData)
    }

    // Used to restore to the second-to-last screenshot when the machine shuts down,
    // so as to avoid having the screenshots all be the same (the Dock moving down and no Menu Bar).
    private var previousScreenshotData: Data?

    func capture() async throws {
        let data = await takeScreenshot()

        guard let data else { return }

        try Task.checkCancellation()

        self.previousScreenshotData = data

        try Task.checkCancellation()

        await MainActor.run {
            self.screenshotSubject.send(data)
        }
    }

    private lazy var context = CIContext()

    private let imageOptions = [
        kCGImageDestinationLossyCompressionQuality: 1,
        kCGImageDestinationImageMaxPixelSize: 4096
    ] as CFDictionary

    private func takeScreenshot() async -> Data? {
        guard let cgImage = await takeScreenshotCGImage() else { return nil }

        return try? cgImage.vb_heicEncodedData(options: imageOptions)
    }

}

// MARK: - Screenshot Taking

private extension VMScreenshotter {
    /// Uses AppKit to take the screenshot from the virtual machine view itself.
    /// This is always used in macOS 13, and can be used in macOS 14 or later if the Virtualization SPI is not available.
    @MainActor
    func takeScreenshotUsingView() -> CGImage? {
        guard let view else { return nil }

        let bounds = view.bounds

        guard bounds.width > 0, bounds.height > 0 else { return nil }

        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }

        view.cacheDisplay(in: bounds, to: bitmapRep)

        guard let cgImage = bitmapRep.cgImage else { return nil }

        return cgImage
    }

    /// Uses new SPI in Virtualization on macOS 14 to take the screenshot from the `VZVirtualMachine` instance.
    /// Currently only takes a screenshot from a single display.
    @available(macOS 14.0, *)
    func takeScreenshotUsingVirtualizationSPI() async -> CGImage? {
        do {
            guard let vm else {
                throw Failure("VM not available")
            }

            let image = try await NSImage.screenshot(from: vm)

            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } catch {
            logger.error("SPI screenshot failed, falling back to view snapshot. Error: \(error, privacy: .public)")
            return await takeScreenshotUsingView()
        }
    }

    /// Returns a `CGImage` with a screenshot of the VM in its current state,
    /// using the best available screenshotting method.
    func takeScreenshotCGImage() async -> CGImage? {
        if #available(macOS 14.0, *) {
            return await takeScreenshotUsingVirtualizationSPI()
        } else {
            return await takeScreenshotUsingView()
        }
    }
}
