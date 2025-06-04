import Cocoa
import SwiftUI
import Combine
import OSLog
import notify

public final class StatusItemManager: NSObject, NSWindowDelegate, StatusItemProvider {

    private lazy var logger: Logger = {
        Logger(subsystem: VirtualUIConstants.subsystemName, category: "StatusItemManager(\(configuration.id))")
    }()

    /// Configures the status item's identity and behavior.
    public struct Configuration {
        /// Unique identifier for this status item.
        public internal(set) var id: String
        /// The behavior for allowing removal of the status item by dragging out of the menu bar.
        public var behavior: NSStatusItem.Behavior
        /// Custom autosave name used by AppKit to store item's on/off and position preferences.
        public var autosaveName: String?

        public static var `default`: Configuration {
            Configuration(id: UUID().uuidString, behavior: .removalAllowed, autosaveName: nil)
        }

        public func id(_ id: String) -> Self {
            var mSelf = self
            mSelf.id = id
            return mSelf
        }

        public init(id: String, behavior: NSStatusItem.Behavior, autosaveName: String? = nil) {
            self.id = id
            self.behavior = behavior
            self.autosaveName = autosaveName
        }
    }
    
    @Published public private(set) var isStatusItemHighlighted: Bool = false

    @Published public private(set) var isPanelVisible = false

    @Published public private(set) var isStatusItemVisible = true

    /// `true` whenever the status item is not actually visible in the Menu Bar.
    /// This differs from `isStatusItemVisible`, which reflects a user-defined setting.
    /// It will be `false` if the status item is not visible in the Menu Bar because not enough space was available,
    /// when using tools such as Bartender to hide status items, or if there's UI covering the status item.
    @Published public private(set) var isStatusItemOccluded = false

    public let willShowPanel = PassthroughSubject<Void, Never>()
    public let willClosePanel = PassthroughSubject<Void, Never>()

    private let configuration: Configuration

    public enum StatusItemView<V: View> {
        case button(label: () -> V)
        case custom(body: () -> V)
    }

    public init<StatusItem: View, Content: View>(configuration: Configuration = .default,
                                          statusItem: StatusItemView<StatusItem>,
                                          content: @escaping @autoclosure () -> Content)
    {
        self.configuration = configuration

        /// This is implemented this way due to a Swift compiler crash 🤦🏻‍♂️
        let group: Group<_ConditionalContent<StatusItemButton<StatusItem, StatusItemManager>, StatusItem>> = Group {
            switch statusItem {
            case .button(let label):
                StatusItemButton<StatusItem, StatusItemManager> {
                    label()
                }
            case .custom(let customBody):
                customBody()
            }
        }

        self.statusItemViewBuilder = {
            AnyView(erasing: group)
        }
        self.contentViewBuilder = {
            AnyView(erasing: content())
        }
        
        super.init()
    }
    
    public convenience init<StatusItem: View, Content: NSViewController>(configuration: Configuration = .default,
                                                                  statusItem: StatusItemView<StatusItem>,
                                                                  content: @escaping @autoclosure () -> Content)
    {
        self.init(
            configuration: configuration,
            statusItem: statusItem,
            content: VUIAppKitViewControllerHost(with: content())
        )
    }
    
    var statusItemToPanelPadding: CGFloat {
        if screenTopInset > 0 { // Tall Menu Bar (i.e. device with notch)
            return 12
        } else { // Short Menu Bar (i.e. device without notch)
            return 5
        }
    }

    private var screenTopInset: CGFloat {
        guard let screen = panel?.screen ?? NSScreen.main else { return 0 }
        return screen.safeAreaInsets.top
    }

    private var statusItemViewBuilder: () -> AnyView
    private var contentViewBuilder: () -> AnyView

    private lazy var cancellables = Set<AnyCancellable>()

    private lazy var item: NSStatusItem = {
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        i.behavior = configuration.behavior
        i.autosaveName = configuration.autosaveName

        return i
    }()

    private var installed = false

    public func install() {
        guard !installed else { return }
        installed = true

        setup()
    }

    private var eventObservers = [Any]()

    private var statusItemWindowCancellable: AnyCancellable?

    private func setup() {
        registerEventObservers()

        item.vui_disableVibrancy()

        let contentView = StatusItemMenuBarExtraView()

        item.vui_contentView = contentView

        let hostingView = NSHostingView(rootView: statusItemViewBuilder().environmentObject(self))

        observeStatusItemOcclusionState(with: hostingView)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        $isPanelVisible.removeDuplicates().dropFirst(1).sink { [weak self] panelVisible in
            guard let self = self else { return }

            if panelVisible {
                self.panelShown()
            } else {
                self.panelHidden()
            }
        }
        .store(in: &cancellables)
    }
    
    /// Call this method when a user preference has changed that affects the visibility of the managed item.
    func visibilityPreferenceChanged(to newValue: Bool) {
        logger.debug("Visibility preference changed to \(newValue, privacy: .public)")
        
        // Set the flag now to prevent delays for possible obsevers that could cause loops.
        isStatusItemVisible = newValue
        item.isVisible = newValue
    }

    private var panel: StatusBarContentPanel?

    public func togglePanelVisible() {
        if isPanelVisible {
            hidePanel()
            isStatusItemHighlighted = false
        } else {
            showPanel()
            isStatusItemHighlighted = true
        }
    }
    
    private var primaryMenuObserver: Any?
    
    public func showPopUpMenu(using builder: () -> NSMenu) {
        guard let view = item.vui_contentView else { return }

        let origin = NSEvent.mouseLocation(in: view)
        
        let menu = builder()

        if menu.responds(to: NSSelectorFromString("setAppearance:")) {
            menu.appearance = NSApp.effectiveAppearance
        }
        
        isStatusItemHighlighted = true
        
        primaryMenuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: menu, queue: .main, using: { [weak self] _ in
            guard let self = self else { return }
            self.primaryMenuObserver = nil
            
            self.isStatusItemHighlighted = false
        })

        menu.popUp(positioning: nil, at: origin, in: view)
    }

    public func showPanel() {
        if let panel {
            guard !panel.isVisible else { return }
        }

        defer { willShowPanel.send() }

        let basePanelSize = NSSize(width: 300, height: 300)

        // These were taken from ControlCenter on macOS 12.4
        let style: NSWindow.StyleMask = [.fullSizeContentView, .nonactivatingPanel]
        let level: NSWindow.Level = .popUpMenu

        let newPanel = StatusBarContentPanel(contentRect: NSRect(origin: .zero, size: basePanelSize), styleMask: style, backing: .buffered, defer: false)
        newPanel.backgroundColor = NSColor.clear
        newPanel.isOpaque = false
        newPanel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        newPanel.hidesOnDeactivate = false
        newPanel.level = level
        newPanel.hasShadow = false
        newPanel.isMovable = false

        let chrome = StatusBarPanelChrome {
            self.contentViewBuilder()
        }

        let contentController = StatusItemPanelContentController(
            child: NSHostingController(rootView: chrome)
        )

        newPanel.contentViewController = contentController

        contentController.view.needsLayout = true

        newPanel.delegate = self

        self.panel = newPanel

        /// Give the system time to perform a layout pass caused by the needsLayout call above,
        /// so that by the time the panel is shown, we already know the size of the contents.
        DispatchQueue.main.async { [self] in
            finishShowingPanel()
        }

        isPanelVisible = true
    }

    private var contentController: StatusItemPanelContentController? {
        panel?.contentViewController as? StatusItemPanelContentController
    }

    private func finishShowingPanel() {
        guard let panel, let contentController else { return }

        contentController.onContentSizeChange = { [weak self] newSize in
            guard let self = self else { return }
            guard let panel = self.panel else { return }
            self.repositionContent(panel, contentSize: newSize, display: true, animate: false)
        }

        repositionContent(
            panel,
            contentSize: contentController.contentSize,
            display: false,
            animate: false
        )

        panel.makeKeyAndOrderFront(nil)
    }

    private func repositionContent(_ panel: NSWindow, contentSize: CGSize, display: Bool, animate: Bool) {
        guard let refView = item.vui_contentView?.superview,
              let refWindow = refView.window else
        {
            assertionFailure("Missing reference status item view or window")
            return
        }

        let reference = refWindow.convertToScreen(refView.frame)

        let panelFrame = NSRect(
            x: reference.midX - contentSize.width / 2,
            y: reference.minY - contentSize.height - statusItemToPanelPadding + StatusBarPanelChromeMetrics.shadowPadding,
            width: contentSize.width,
            height: contentSize.height
        )

        #if DEBUG
        logger.debug("⬛️ contentSize = \(contentSize.width, privacy: .public)x\(contentSize.height, privacy: .public)")
        #endif

        panel.setFrame(panelFrame, display: display, animate: animate)
    }

    private var panelIsClosing = false

    public func hidePanel(animated: Bool = true) {
        guard isPanelVisible, !panelIsClosing else { return }

        guard animated else {
            panel?.close()
            return
        }

        panelIsClosing = true

        NSAnimationContext.runAnimationGroup { [weak self] ctx in
            guard let panel = self?.panel else { return }
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            defer { self?.panelIsClosing = false}

            guard let panel = self?.panel else { return }

            panel.close()
        }
    }

    public func windowWillClose(_ notification: Notification) {
        willClosePanel.send()
        
        DispatchQueue.main.async {
            self.panel = nil
            self.isStatusItemHighlighted = false
            self.isPanelVisible = false
        }
    }

    public func windowDidResignKey(_ notification: Notification) {
        logger.debug("🔑 RESIGNED KEY")

        delayedHidePanel()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        logger.debug("🔑 BECAME KEY")

        panelHideDelayItem?.cancel()
        panelHideDelayItem = nil
    }

    private var panelHideDelayItem: DispatchWorkItem?

    private func delayedHidePanel() {
        panelHideDelayItem?.cancel()
        panelHideDelayItem = nil

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            guard self.isPanelVisible, !self.panelIsClosing else { return }

            /// Do not hide if we're showing a sheet in the panel, which can happen for alerts.
            guard self.panel?.sheets.isEmpty == true else {
                self.logger.debug("Panel hiding due to resigning key cancelled: showing a sheet")
                return
            }

            self.logger.debug("Hiding panel due to window resigning key")

            self.hidePanel()
        }

        panelHideDelayItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
    
    private var highlightOffWorkItem: DispatchWorkItem?
    
    func flash() {
        highlightOffWorkItem?.cancel()
        highlightOffWorkItem = nil
        
        isStatusItemHighlighted = true
        let item = DispatchWorkItem { [weak self] in
            self?.isStatusItemHighlighted = false
            self?.highlightOffWorkItem = nil
        }
        highlightOffWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    private func observeStatusItemOcclusionState(with hostingView: NSView) {
        hostingView.publisher(for: \.window, options: [.initial, .new]).sink { [weak self] window in
            guard let self = self else { return }

            self.statusItemWindowCancellable = nil

            self.logger.debug("🤲🏻 Status item host window: \(String(describing: window), privacy: .public)")

            guard let window else { return }

            self.evaluateStatusItemOcclusion(in: window)

            self.statusItemWindowCancellable = NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window).sink(receiveValue: { note in
                guard let w = note.object as? NSWindow else { return }

                self.logger.debug("🤲🏻 Status item host window occlusion state: \(w.occlusionState.description, privacy: .public)")

                self.evaluateStatusItemOcclusion(in: w)
            })
        }
        .store(in: &cancellables)
    }

    private func evaluateStatusItemOcclusion(in window: NSWindow) {
        let newState = !window.occlusionState.isVisible

        guard newState != isStatusItemOccluded else { return }

        isStatusItemOccluded = newState

        logger.debug("🤲🏻 isStatusItemOccluded = \(newState, privacy: .public)")
    }

    deinit {
        unregisterEventObservers()
    }

}

// MARK: - Menu Bar Integration

private extension StatusItemManager {

    private func panelShown() {
        logger.debug("🪟 \(#function, privacy: .public)")

        postBeginMenuTrackingNotification()

        NSApplication.shared.__vui_setMenuBarVisible(true)

        notify_post("com.apple.hitoolbox.menubar.position.lock")
    }

    private func panelHidden() {
        logger.debug("🪟 \(#function, privacy: .public)")

        postEndMenuTrackingNotification()

        notify_post("com.apple.hitoolbox.menubar.position.unlock")
    }

    func postBeginMenuTrackingNotification() {
        let name = "com.apple.HIToolbox.beginMenuTrackingNotification"

        let pidStr = "\(ProcessInfo.processInfo.processIdentifier)"
        logger.debug("🪟 \(name, privacy: .public) \(pidStr, privacy: .public)")

        DistributedNotificationCenter.default().post(name: .init(name), object: pidStr)
    }

    func postEndMenuTrackingNotification() {
        let name = "com.apple.HIToolbox.endMenuTrackingNotification"

        let pidStr = "\(ProcessInfo.processInfo.processIdentifier)"
        logger.debug("🪟 \(name, privacy: .public) \(pidStr, privacy: .public)")

        DistributedNotificationCenter.default().post(name: .init(name), object: pidStr)
    }

    func registerEventObservers() {
        let clickOutsideObserver = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self else { return }

            self.hidePanel()
        }
        if let clickOutsideObserver { eventObservers.append(clickOutsideObserver) }

        let statusItemVisibilityObserver = item.observe(\.isVisible, options: [.new, .old], changeHandler: { [weak self] _, change in
            guard let self = self else { return }
            guard let newValue = change.newValue else { return }
            guard newValue != change.oldValue, newValue != self.isStatusItemVisible else { return }
            
            self.logger.debug("Status item visibility changed to \(newValue, privacy: .public)")

            self.isStatusItemVisible = newValue
        })
        eventObservers.append(statusItemVisibilityObserver)
    }

    func unregisterEventObservers() {
        eventObservers.removeAll()
    }

}

extension NSEvent {
    
    /// Returns the current mouse cursor location relative to the view's coordinate space.
    /// Handy for popping up contextual menus in response to clicking a view.
    static func mouseLocation(in view: NSView) -> NSPoint {
        let mp = NSEvent.mouseLocation

        guard let window = view.window else { return mp }
        
        let p = window.convertFromScreen(NSRect(origin: mp, size: CGSize(width: 1, height: 1)))
        
        return view.convert(p, from: nil).origin
    }
    
    /// Returns the current mouse cursor location relative to the view's coordinate space.
    /// Handy for popping up contextual menus in response to clicking a view.
    static func mouseLocation(in window: NSWindow) -> NSPoint {
        let mp = NSEvent.mouseLocation

        return window.convertFromScreen(NSRect(origin: mp, size: CGSize(width: 1, height: 1))).origin
    }
    
}

extension NSWindow.OcclusionState: @retroactive CustomStringConvertible {
    public var description: String {
        return isVisible ? "\(rawValue) (Visible)" : "\(rawValue) (Hidden)"
    }

    var isVisible: Bool { isStrictSuperset(of: .visible) }
}
