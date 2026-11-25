import AppKit
import OSLog

/// Implemented by the object that owns the panel presented from a status item managed by ``StatusItemController``.
@MainActor
public protocol StatusItemControllerDelegate: AnyObject {
    /// The window currently presenting the status item's panel, `nil` if the panel is not being presented.
    func statusItemControllerPanelWindow(_ controller: StatusItemController) -> NSWindow?

    /// Called shortly before the controller asks for the panel to be shown.
    func statusItemControllerWillShowPanel(_ controller: StatusItemController)

    /// The delegate must present the status item's panel.
    func statusItemControllerDidRequestShowPanel(_ controller: StatusItemController)

    /// The delegate must dismiss the status item's panel.
    func statusItemControllerDidRequestHidePanel(_ controller: StatusItemController, animated: Bool)
}

/// Coordinates the presentation of a custom panel from a status item.
///
/// The controller decides when the panel should be shown or hidden in response to user interaction,
/// the delegate is responsible for the panel itself, which is typically a ``StatusBarMenuWindowController``.
///
/// In macOS 27 and later, presentation is driven by the system through an expanded interface session,
/// which makes the status item participate in menu bar tracking and keyboard navigation.
/// In earlier versions, the controller handles clicks on the status item and the escape key by itself.
@MainActor
public final class StatusItemController: NSObject {
    private let logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: String(describing: StatusItemController.self))

    public let statusItem: NSStatusItem
    public weak var delegate: StatusItemControllerDelegate?

    public init(statusItem: NSStatusItem, delegate: StatusItemControllerDelegate?) {
        self.statusItem = statusItem
        self.delegate = delegate

        super.init()
    }

    /// Starts handling interaction with the status item.
    public func configure() {
        if #available(macOS 27, *) {
            statusItem.expandedInterfaceDelegate = self
        } else {
            statusItem.button?.target = self
            statusItem.button?.action = #selector(togglePanel)
        }
    }

    // MARK: - Panel Visibility

    private var panelWindow: NSWindow? { delegate?.statusItemControllerPanelWindow(self) }

    public var isPanelVisible: Bool { panelWindow?.isVisible == true }

    @objc public func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    public func showPanel() {
        guard !isPanelVisible else { return }

        if statusItem.vui_requestExpandedInterfaceSession() {
            logger.debug("Requested expanded interface session")
        } else {
            requestShowPanel()
        }
    }

    public func hidePanel(animated: Bool = true) {
        if #available(macOS 27, *), let session = statusItem.expandedInterfaceSession {
            logger.debug("Cancelling expanded interface session")

            /// The panel is hidden when the delegate is notified about the end of the session.
            session.cancel()
        } else {
            requestHidePanel(animated: animated)
        }
    }

    private func requestShowPanel() {
        logger.debug(#function)

        activateEventMonitors()

        delegate?.statusItemControllerWillShowPanel(self)
        delegate?.statusItemControllerDidRequestShowPanel(self)
    }

    private func requestHidePanel(animated: Bool) {
        logger.debug(#function)

        invalidateEventMonitors()

        delegate?.statusItemControllerDidRequestHidePanel(self, animated: animated)
    }

    // MARK: - Events

    private lazy var clickAwayMonitor = ManagedEventMonitor(mask: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event, scope in
        self?.handleClickAway(with: event, scope: scope)
        return true
    }

    private lazy var escapeKeyMonitor = ManagedEventMonitor(mask: .keyDown, scope: .local) { [weak self] event, _ in
        guard let self, event.keyCode == Self.escapeKeyCode else { return true }

        hidePanel()

        return false
    }

    private static let escapeKeyCode: UInt16 = 53

    private func activateEventMonitors() {
        clickAwayMonitor.activate()

        /// The system handles the escape key for expanded interface sessions.
        if #unavailable(macOS 27) {
            escapeKeyMonitor.activate()
        }
    }

    private func invalidateEventMonitors() {
        clickAwayMonitor.invalidate()
        escapeKeyMonitor.invalidate()
    }

    private func handleClickAway(with event: NSEvent, scope: ManagedEventMonitor.Scope) {
        guard scope == .local else {
            /// Clicks in other apps always dismiss the panel.
            hidePanel()
            return
        }

        /// Clicks within this app only dismiss the panel when they land on a window that's unrelated to the status item and its panel.
        guard let clickedWindow = event.window, let panelWindow else { return }
        guard clickedWindow !== statusItem.button?.window else { return }
        guard !clickedWindow.vui_isSelfOrDescendant(of: panelWindow) else { return }

        hidePanel()
    }
}

// MARK: - Expanded Interface Session

@available(macOS 27, *)
extension StatusItemController: @MainActor NSStatusItemExpandedInterfaceDelegate {
    public func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        logger.debug("Expanded interface session began")

        requestShowPanel()
    }

    public func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        logger.debug("Expanded interface session ended")

        requestHidePanel(animated: animated)
    }
}

private extension NSWindow {
    /// `true` if the window is the specified window, or if it's presented from it as a sheet or child window, at any depth.
    func vui_isSelfOrDescendant(of ancestor: NSWindow) -> Bool {
        var candidate: NSWindow? = self

        while let window = candidate {
            if window === ancestor { return true }
            candidate = window.sheetParent ?? window.parent
        }

        return false
    }
}
