import AppKit
import SwiftUI
import OSLog

/// Presents SwiftUI content in a panel attached to a status item, similar to the ones used by system menu bar extras.
///
/// The panel sizes itself to fit its content and remains positioned below the status item as the content's size changes.
/// A window controller is good for a single presentation: create a new one every time the panel needs to be shown,
/// using ``windowWillClose`` in order to find out when the current one can be discarded.
@MainActor
public final class StatusBarMenuWindowController: NSWindowController {
    private let logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: String(describing: StatusBarMenuWindowController.self))

    public let statusItem: NSStatusItem

    /// Invoked shortly before the panel is closed.
    public var windowWillClose: (_ controller: StatusBarMenuWindowController) -> Void = { _ in }

    private let hostingController: NSViewController

    private var contentSizeObservation: NSKeyValueObservation?
    private var screenParametersObservation: NSObjectProtocol?

    public init(statusItem: NSStatusItem, rootView: some View) {
        self.statusItem = statusItem

        let hostingController = NSHostingController(rootView: rootView.modifier(StatusBarMenuChrome()))
        hostingController.sizingOptions = .preferredContentSize
        self.hostingController = hostingController

        let panel = StatusBarMenuPanel()
        panel.contentViewController = hostingController

        super.init(window: panel)

        panel.delegate = self
    }

    public required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - Visibility

    /// Keeps the menu bar visible while the panel is key, only used in macOS versions before macOS 27.
    private var menuBarVisibilityAssertion: MenuBarVisibilityAssertion?

    /// Identifies the animated close currently in flight, so that showing the panel again before it finishes cancels the close.
    private var closeToken: UUID?

    public override func showWindow(_ sender: Any?) {
        startObservingLayoutChanges()

        closeToken = nil

        repositionWindow()

        window?.alphaValue = 1

        super.showWindow(sender)
    }

    public override func close() {
        close(animated: false)
    }

    public func close(animated: Bool) {
        guard let window, window.isVisible else { return }

        stopObservingLayoutChanges()

        guard animated else {
            closeToken = nil
            super.close()
            return
        }

        let token = UUID()
        closeToken = token

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.closeAnimationDuration
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.closeToken == token else { return }
                self.close(animated: false)
            }
        }
    }

    /// Stops keeping the menu bar visible in case the panel is currently doing so.
    ///
    /// The app must call this before terminating and then give the system enough time to process the change,
    /// otherwise the menu bar might remain permanently visible after the app is gone.
    public func unlockMenuBar() {
        menuBarVisibilityAssertion?.invalidate()
        menuBarVisibilityAssertion = nil
    }

    // MARK: - Layout

    private enum Metrics {
        /// Distance between the bottom of the menu bar and the top of the panel.
        static let menuBarSpacing: CGFloat = 6
        /// Minimum distance between the panel and the horizontal edges of the screen.
        static let screenMargin: CGFloat = 8
        static let closeAnimationDuration: TimeInterval = 0.15
    }

    private func startObservingLayoutChanges() {
        guard contentSizeObservation == nil else { return }

        contentSizeObservation = hostingController.observe(\.preferredContentSize) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.repositionWindow()
            }
        }

        screenParametersObservation = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionWindow()
            }
        }
    }

    private func stopObservingLayoutChanges() {
        contentSizeObservation?.invalidate()
        contentSizeObservation = nil

        if let screenParametersObservation {
            NotificationCenter.default.removeObserver(screenParametersObservation)
            self.screenParametersObservation = nil
        }
    }

    /// Sizes the panel to fit its content, placing it below the status item.
    private func repositionWindow() {
        guard let window else { return }

        let size = hostingController.view.fittingSize

        guard let anchorWindow = statusItem.button?.window, statusItem.isVisible, let screen = anchorWindow.screen else {
            logger.debug("Status item is not on screen, centering panel instead")

            window.setContentSize(size)
            window.center()

            return
        }

        /// The panel's frame includes transparent padding that leaves room for its shadow, which is allowed to extend past the area available for its chrome.
        let padding = StatusBarMenuChromeMetrics.shadowPadding
        let anchorFrame = anchorWindow.frame
        let availableFrame = screen.visibleFrame.insetBy(dx: Metrics.screenMargin - padding, dy: 0)

        var x = anchorFrame.midX - size.width / 2
        x = min(x, availableFrame.maxX - size.width)
        x = max(x, availableFrame.minX)

        let y = anchorFrame.minY - Metrics.menuBarSpacing + padding - size.height

        let frame = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)

        guard frame != window.frame else { return }

        window.setFrame(frame, display: true)
    }
}

// MARK: - Window Delegate

extension StatusBarMenuWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        stopObservingLayoutChanges()
        unlockMenuBar()
        setStatusItemHighlighted(false)

        windowWillClose(self)

        /// Prevents the SwiftUI hierarchy and its environment from outliving the presentation.
        window?.contentViewController = nil
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        setStatusItemHighlighted(true)

        if #unavailable(macOS 27) {
            menuBarVisibilityAssertion = NSApp.requestMenuBarVisible()
        }
    }

    public func windowDidResignKey(_ notification: Notification) {
        setStatusItemHighlighted(false)
        unlockMenuBar()
    }
}

// MARK: - Status Item Highlight

private extension StatusBarMenuWindowController {
    /// The system takes care of highlighting the status item for expanded interface sessions in macOS 27 and later.
    func setStatusItemHighlighted(_ highlighted: Bool) {
        guard #unavailable(macOS 27) else { return }

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(highlightStatusItem), object: nil)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(dimStatusItem), object: nil)

        /// Deferred because the button resets its own highlight when it finishes tracking the click that caused the panel to be presented.
        perform(highlighted ? #selector(highlightStatusItem) : #selector(dimStatusItem), with: nil, afterDelay: 0)
    }

    @objc func highlightStatusItem() {
        statusItem.button?.highlight(true)
    }

    @objc func dimStatusItem() {
        statusItem.button?.highlight(false)
    }
}

// MARK: - Panel

private final class StatusBarMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        /// The shadow is drawn by the content's chrome.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
