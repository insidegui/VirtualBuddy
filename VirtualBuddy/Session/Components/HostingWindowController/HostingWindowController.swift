//
//  HostingWindowController.swift
//  StatusBuddy
//
//  Created by Guilherme Rambo on 21/12/21.
//  Copyright © 2021 Guilherme Rambo. All rights reserved.
//

import Cocoa
import SwiftUI

let defaultHostingWindowStyleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]

public final class HostingWindowController<Content>: NSWindowController, NSWindowDelegate where Content: View {

    /// Invoked shortly before the hosting window controller's window is closed.
    public var willClose: ((HostingWindowController<Content>) -> Void)?
    
    private static func makeDefaultWindow() -> NSWindow {
        HostingWindow(
            contentRect: NSRect(x: 0, y: 0, width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric),
            styleMask: defaultHostingWindowStyleMask,
            backing: .buffered,
            defer: false,
            screen: nil
        )
    }

    public init(rootView: Content, windowFactory: (() -> NSWindow)? = nil) {
        let window = windowFactory?() ?? Self.makeDefaultWindow()
        
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
        
        willClose?(self)
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

fileprivate final class HostingWindow: NSWindow {
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var confirmBeforeClosingCallback: () async -> Bool = { true }

    override func close() {
        Task {
            guard await confirmBeforeClosingCallback() else { return }
            await MainActor.run { closeWithoutConfirmation() }
        }
    }

    private func closeWithoutConfirmation() {
        super.close()
    }
    
}
