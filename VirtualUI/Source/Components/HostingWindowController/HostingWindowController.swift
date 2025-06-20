import Cocoa
import SwiftUI
import VirtualCore

let defaultHostingWindowStyleMask: NSWindow.StyleMask = [.titled, .miniaturizable, .resizable, .closable, .fullSizeContentView]

public final class HostingWindowController<Content>: NSWindowController, NSWindowDelegate where Content: View {

    public typealias WindowCloseBlock = ((HostingWindowController<Content>) -> Void)

    /// Invoked shortly before the hosting window controller's window is closed.
    private var onWindowClose: WindowCloseBlock?

    private static func makeDefaultWindow() -> NSWindow {
        HostingWindow(
            contentRect: NSRect(x: 0, y: 0, width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric),
            styleMask: defaultHostingWindowStyleMask,
            backing: .buffered,
            defer: false,
            screen: nil
        )
    }

    public init(id: String? = nil, rootView: Content, windowFactory: (() -> NSWindow)? = nil, onWindowClose: WindowCloseBlock? = nil) {
        let window = windowFactory?() ?? Self.makeDefaultWindow()

        if let id {
            window.identifier = .init(id)
        }
        
        super.init(window: window)

        let controller = NSHostingController(
            rootView: rootView
                .environment(\.closeWindow, { [weak self] in self?.close() })
                .environment(\.cocoaWindow, window)
        )
        
        contentViewController = controller
        window.setContentSize(controller.view.fittingSize)
        
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.onWindowClose = onWindowClose
    }
    
    public required init?(coder: NSCoder) {
        fatalError()
    }
    
    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        
        window?.center()
    }

    public func windowWillClose(_ notification: Notification) {
        contentViewController = nil
        
        onWindowClose?(self)
        
        /// Ensures references in the closure are not retained past the lifetime of the window.
        /// Opening a new hosting window controller requires going through ``OpenCocoaWindowAction``,
        /// which sets up the callback again if needed.
        onWindowClose = nil
    }
    
    var viewRendersWindowChrome: Bool = false {
        didSet {
            guard viewRendersWindowChrome != oldValue else { return }
            DispatchQueue.main.async { self.configureChrome() }
        }
    }
    
    private func configureChrome() {
        if viewRendersWindowChrome {
            window?.styleMask.remove(.titled)
            window?.styleMask.insert(.borderless)
            window?.backgroundColor = .clear
            window?.isOpaque = false
        } else {
            window?.styleMask.remove(.borderless)
            window?.styleMask.insert(.titled)
            window?.backgroundColor = .windowBackgroundColor
            window?.isOpaque = true
        }
    }
    
    var onWindowOcclusionStateChanged: ((NSWindow.OcclusionState) -> Void)? = nil
    
    public func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let state = window?.occlusionState else { return }
        onWindowOcclusionStateChanged?(state)
    }
    
    public func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        [
            .autoHideDock,
            .autoHideMenuBar,
            .autoHideToolbar,
            .fullScreen
        ]
    }

    var confirmBeforeClosingCallback: () async -> Bool {
        get {
            guard let hostingWindow = window as? HostingWindow else {
                preconditionFailure("confirmBeforeClosing can't be used with custom window types in HostingWindowController")
            }
            return hostingWindow.confirmBeforeClosingCallback
        }
        set {
            precondition(window is HostingWindow, "confirmBeforeClosing can't be used with custom window types in HostingWindowController")
            (window as? HostingWindow)?.confirmBeforeClosingCallback = newValue
        }
    }
    
}

extension HostingWindowController: WindowChromeConsumer { }

protocol WindowChromeConsumer: AnyObject {
    var viewRendersWindowChrome: Bool { get set }
    var onWindowOcclusionStateChanged: ((NSWindow.OcclusionState) -> Void)? { get set }
    var confirmBeforeClosingCallback: () async -> Bool { get set }
}

fileprivate final class HostingWindow: VBRestorableWindow {
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var confirmBeforeClosingCallback: () async -> Bool = { true }

    var enableMemoryLeakAssertion = true

    override func performClose(_ sender: Any?) {
        /// This addresses a weird issue introduced after #257 where for some reason `VMController`
        /// was being retained by a SwiftUI button when closing a VM window using Command+W
        /// after opening multiple VM windows.
        /// The button that was retaining the controller though a closure context was one of
        /// the toolbar buttons, and for some reason not going directly through our `close()`
        /// implementation here was triggering the leak :(
        close()
    }

    override func close() {
        Task { @MainActor in
            guard await confirmBeforeClosingCallback() else { return }
            await MainActor.run { closeWithoutConfirmation() }
        }
    }

    private func closeWithoutConfirmation() {
        super.close()

        VBMemoryLeakDebugAssertions.vb_objectShouldBeReleasedSoon(self)
    }

    deinit {
        VBMemoryLeakDebugAssertions.vb_objectIsBeingReleased(self)
    }

}
