// WIP
////
////  FullScreenWindowController.swift
////  CustomFullScreen
////
////  Created by Guilherme Rambo on 13/05/22.
////
//
//import Cocoa
//import SwiftUI
//
///// Adopted by content that can be put into full screen mode via ``FullScreenWindowController``.
//protocol FullScreenContentProviding: NSObjectProtocol {
//    
//    /// Implemented to return a custom representation of the content for full screen display.
//    /// - Returns: An ``NSViewController`` representing the content for full screen presentation.
//    func fullScreenRepresentation() -> NSViewController?
//    
//    /// Called when the view controller is about to enter full screen mode.
//    func willEnterFullScreen()
//
//    /// Called when the view controller has finished entering full screen mode.
//    func didEnterFullScreen()
//    
//    /// Called when the view controller is about to exit full screen mode.
//    func willExitFullScreen()
//    
//    /// Called when the view controller has existing entering full screen mode.
//    func didExitFullScreen()
//    
//}
//
//extension FullScreenContentProviding {
//    func willEnterFullScreen() { }
//    func didEnterFullScreen() { }
//    func willExitFullScreen() { }
//    func didExitFullScreen() { }
//}
//
//extension NSViewController {
//    
//    var fullScreenWindowController: FullScreenWindowController? {
//        view.window?.windowController as? FullScreenWindowController
//    }
//    
//    var isInFullScreen: Bool {
//        fullScreenWindowController?.isInFullScreenMode == true
//    }
//    
//}
//
//extension NSHostingController: FullScreenContentProviding {
//    
//    func fullScreenRepresentation() -> NSViewController? {
//        NSHostingController(rootView: rootView)
//    }
//    
//}
//
///// A window controller that can present a view controller in full screen.
//@MainActor
//class FullScreenWindowController: NSWindowController, NSWindowDelegate {
//    
//    private static let presenter = FullScreenContentPresenter()
//    
//    /// Called with `true` when the mouse is over an area of the window that should
//    /// reveal the titlebar  / toolbar, `false` when the mouse leaves the area.
//    var titleBarRevealCallback: (Bool) -> Void = { _ in }
//    
//    /// Creates a managed controller and presents the content in full screen.
//    /// - Parameters:
//    ///   - controller: The ``NSViewController`` that will be presented in full screen.
//    ///   Implement the ``FullScreenContentProviding`` protocol to customize the content
//    ///   for full screen presentation.
//    ///   - screen: The screen where the full screen contents should be presented.
//    ///
//    ///   The full screen window controller will be managed automatically and released from memory when
//    ///   full screen presentation is dismissed. There is no need to retain a strong reference to the instance that's returned.
//    @discardableResult
//    class func present(_ controller: NSViewController, on screen: NSScreen? = nil) -> FullScreenWindowController {
//        presenter.present(controller, on: screen)
//    }
//    
//    /// Toggles full screen for the specified view controller, managing the full screen window controller automatically.
//    /// - Parameter controller: The controller that provides the full screen content.
//    class func toggleFullScreen(for controller: NSViewController) {
//        if controller.isInFullScreen {
//            presenter.dismiss(controller)
//        } else {
//            presenter.present(controller, on: controller.view.window?.screen)
//        }
//    }
//    
//    class func dismiss(_ controller: NSViewController) {
//        guard controller.isInFullScreen else { return }
//        presenter.dismiss(controller)
//    }
//
//    let contentController: NSViewController
//    let screen: NSScreen
//    private let fullScreenRect: NSRect
//    private weak var sourceWindow: NSWindow?
//
//    private let fullScreenWindowLevel: NSWindow.Level = .normal
//    
//    /// Creates a full screen window controller for a given content controller.
//    /// - Parameters:
//    ///   - contentController: An ``NSViewController`` that will be presented in full screen when
//    ///   ``present()`` is called. Implement the ``FullScreenContentProviding`` protocol
//    ///   to customize the content for full screen presentation.
//    ///   - screen: The screen where the full screen contents should be presented.
//    ///
//    ///   You can instantiate a ``FullScreenWindowController`` and manage it yourself
//    ///   or call the ``FullScreenWindowController/present(_:on:)`` class method
//    ///   to present a view controller in full screen, in which case the window controller will be managed automatically.
//    init(contentController: NSViewController, screen: NSScreen?) {
//        self.contentController = contentController
//        self.sourceWindow = contentController.view.window
//        
//        guard let effectiveScreen = screen ?? NSScreen.main else {
//            fatalError("No screens available")
//        }
//        
//        self.screen = effectiveScreen
//        self.fullScreenRect = effectiveScreen.frame
//        
//        let frame = NSRect(origin: .zero, size: effectiveScreen.frame.size)
//        
//        let window = FullScreenWindow(
//            contentRect: frame,
//            styleMask: [.closable, .fullSizeContentView],
//            backing: .buffered,
//            defer: false,
//            screen: effectiveScreen
//        )
//        
//        super.init(window: window)
//
//        window.hasShadow = true
//        window.titlebarAppearsTransparent = true
//        window.titleVisibility = .hidden
//        window.collectionBehavior = [.fullScreenPrimary, .participatesInCycle, .managed, .canJoinAllSpaces]
//        window.isMovable = false
//        window.backgroundColor = sourceWindow?.backgroundColor ?? .windowBackgroundColor
//        window.title = sourceWindow?.title ?? ""
//        window.delegate = self
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("Hard nope")
//    }
//    
//    private var contentProvider: FullScreenContentProviding? {
//        contentController as? FullScreenContentProviding
//    }
//    
//    private lazy var effectiveContentController: NSViewController = {
//        if let provider = contentProvider,
//           let customContent = provider.fullScreenRepresentation()
//        {
//            return customContent
//        } else {
//            return contentController
//        }
//    }()
//    
//    private var currentWindowFrame: NSRect { window?.frame ?? .zero }
//
//    private class func bestScreenRectFromDetachingContainer(_ containerView: NSView?) -> NSRect {
//        guard let view = containerView, let superview = view.superview else { return NSRect.zero }
//
//        return view.window?.convertToScreen(superview.convert(view.frame, to: nil)) ?? NSRect.zero
//    }
//    
//    private weak var originalContainer: NSView?
//    
//    private var sourceRect: NSRect = .zero
//    
//    private func calculateSourceRect() -> NSRect  {
//        let rect = Self.bestScreenRectFromDetachingContainer(contentController.view)
//        
//        return rect
//    }
//    
//    private(set) var isInFullScreenMode = false
//    
//    func present() {
//        assert(effectiveContentController.view !== effectiveContentController.view.window?.contentView,
//               "Full screen presentation is not supported when the controller's view is its window's contentView. Please wrap your controller's view in another view.")
//        
//        isInFullScreenMode = true
//        
//        originalContainer = contentController.view.superview
//        sourceRect = calculateSourceRect()
//        
//        contentViewController = effectiveContentController
//        
//        window?.setFrame(sourceRect, display: false)
//        
//        showWindow(nil)
//        
//        contentProvider?.willEnterFullScreen()
//        
//        perform(#selector(runEnterFullScreenAnimation), with: nil, afterDelay: 0)
//    }
//    
//    func dismiss() {
//        contentProvider?.willExitFullScreen()
//        
//        isInFullScreenMode = false
//        
//        perform(#selector(runExitFullScreenAnimation), with: nil, afterDelay: 0)
//    }
//    
//    private var animationDuration: TimeInterval {
//        NSEvent.modifierFlags.contains(.shift) ? 5 : 0.5
//    }
//    
//    private func configureAnimation(in context: NSAnimationContext) {
//        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
//        context.duration = animationDuration
//    }
//    
//    @objc private func runEnterFullScreenAnimation() {
//        guard let window = window else { return }
//        
//        configureForEnteringFullScreen()
//        
//        NSAnimationContext.runAnimationGroup { ctx in
//            configureAnimation(in: ctx)
//            window.animator().setFrame(fullScreenRect, display: false)
//        } completionHandler: {
//            self.contentProvider?.didEnterFullScreen()
//        }
//    }
//    
//    @objc private func runExitFullScreenAnimation() {
//        guard let window = window else { return }
//        
//        configureForExitingFullScreen()
//
//        NSAnimationContext.runAnimationGroup { ctx in
//            configureAnimation(in: ctx)
//            window.animator().setFrame(sourceRect, display: false)
//        } completionHandler: {
//            self.close()
//            
//            self.reattachContentToSource()
//            
//            self.contentProvider?.didExitFullScreen()
//        }
//    }
//    
//    private func reattachContentToSource() {
//        guard let originalContainer = originalContainer else {
//            return
//        }
//
//        contentController.view.frame = originalContainer.bounds
//        let view = contentController.view
//
//        originalContainer.addSubview(view)
//
//        originalContainer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|-(0)-[playerView]-(0)-|", options: [], metrics: nil, views: ["playerView": view]))
//        originalContainer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(0)-[playerView]-(0)-|", options: [], metrics: nil, views: ["playerView": view]))
//    }
//
//    private let fullScreenPresentationOptions: [NSApplication.PresentationOptions] = [
//        .autoHideDock,
//        .autoHideMenuBar,
//        .autoHideToolbar,
//        .fullScreen
//    ]
//    
//    private func configureForEnteringFullScreen() {
//        window?.level = fullScreenWindowLevel
//        
//        fullScreenPresentationOptions.forEach {
//            NSApp?.presentationOptions.insert($0)
//        }
//        
//        installTitleBarRevealEvent()
//    }
//    
//    private func configureForExitingFullScreen() {
//        originalContainer?.window?.makeKeyAndOrderFront(self)
//        
//        fullScreenPresentationOptions.forEach {
//            NSApp?.presentationOptions.remove($0)
//        }
//    }
//    
//    private var titleBarRevealMonitor: Any?
//
//    private func installTitleBarRevealEvent() {
//        titleBarRevealMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
//            guard let self = self else { return nil }
//            self.revealTitleBarIfNeeded(with: event)
//            return event
//        }
//    }
//    
//    private let titleBarRevealHeight = CGFloat(60)
//    
//    private var titleBarRevealRect: NSRect {
//        NSRect(x: 0, y: currentWindowFrame.height - titleBarRevealHeight, width: currentWindowFrame.width, height: titleBarRevealHeight)
//    }
//    
//    private func revealTitleBarIfNeeded(with event: NSEvent) {
//        let isInRevealArea = titleBarRevealRect.contains(event.locationInWindow)
//        
//        titleBarRevealCallback(isInRevealArea)
//    }
//    
//    deinit {
//        if let titleBarRevealMonitor = titleBarRevealMonitor {
//            NSEvent.removeMonitor(titleBarRevealMonitor)
//        }
//    }
//
//}
//
//@MainActor
//fileprivate final class FullScreenWindow: NSWindow {
//    
//    override var canBecomeKey: Bool { true }
//    override var canBecomeMain: Bool { true }
//    override var acceptsFirstResponder: Bool { true }
//
//    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
//        frameRect
//    }
//    
//    override func standardWindowButton(_ b: NSWindow.ButtonType) -> NSButton? {
//        guard let button = super.standardWindowButton(b) else { return nil }
//        
//        button.alphaValue = 0
//        button.isHidden = true
//        
//        return button
//    }
//    
//}
//
//@MainActor
//fileprivate final class FullScreenContentPresenter {
//    
//    private lazy var fullScreenControllers = [Int: FullScreenWindowController]()
//    
//    @discardableResult
//    func present(_ controller: NSViewController, on screen: NSScreen?) -> FullScreenWindowController {
//        let windowController = FullScreenWindowController(contentController: controller, screen: screen)
//        fullScreenControllers[controller.hash] = windowController
//        windowController.present()
//        return windowController
//    }
//    
//    func dismiss(_ controller: NSViewController) {
//        fullScreenControllers[controller.hash]?.dismiss()
//    }
//    
//}
