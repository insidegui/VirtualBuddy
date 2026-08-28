//
//  SwiftUIVMView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import Cocoa
import BuddyUI
import Virtualization
import VirtualCore

/// Controls the input events that are delivered to the virtual machine.
struct VMEventDeliveryMask: OptionSet, Sendable, CustomStringConvertible {
    let rawValue: UInt32

    static let keyboard = VMEventDeliveryMask(rawValue: 1 << 0)
    static let mouse = VMEventDeliveryMask(rawValue: 1 << 1)

    static let all: VMEventDeliveryMask = [.keyboard, .mouse]
    static let none: VMEventDeliveryMask = []

    var description: String {
        guard !isEmpty else { return "<empty>" }

        var elements = [String]()
        if contains(.mouse) { elements.append("mouse") }
        if contains(.keyboard) { elements.append("keyboard") }
        return elements.joined(separator: "|")
    }
}


private extension EnvironmentValues {
    @Entry var virtualMachineEventDeliveryMask = VMEventDeliveryMask.all
}

extension View {
    func virtualMachineEventDeliveryMask(_ mask: VMEventDeliveryMask) -> some View {
        environment(\.virtualMachineEventDeliveryMask, mask)
    }
}

struct SwiftUIVMView: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = VMViewController
    
    @Binding var controllerState: VMController.State
    let captureSystemKeysEnabled: Bool
    var isDFUModeVM: Bool
    var vmECID: UInt64?
    @Binding var automaticallyReconfiguresDisplay: Bool

    func makeNSViewController(context: Context) -> VMViewController {
        let controller = VMViewController()
        controller.vmECID = vmECID
        controller.isDFUModeVM = isDFUModeVM
        controller.captureSystemKeysEnabled = captureSystemKeysEnabled
        controller.automaticallyReconfiguresDisplay = automaticallyReconfiguresDisplay
        return controller
    }
    
    func updateNSViewController(_ nsViewController: VMViewController, context: Context) {
        nsViewController.automaticallyReconfiguresDisplay = automaticallyReconfiguresDisplay

        nsViewController.vmECID = vmECID
        nsViewController.isDFUModeVM = isDFUModeVM
        nsViewController.eventDeliveryMask = context.environment.virtualMachineEventDeliveryMask

        if case .running(let vm) = controllerState {
            nsViewController.virtualMachine = vm
        } else {
            nsViewController.virtualMachine = nil
        }
    }

}

final class VMViewController: NSViewController {

    var isDFUModeVM: Bool = false {
        didSet {
            guard isDFUModeVM != oldValue, isViewLoaded else { return }

            handleDFUTransition(.init(wasInDFU: oldValue, isInDFU: isDFUModeVM))
        }
    }

    var vmECID: UInt64? {
        didSet {
            guard vmECID != nil, vmECID != oldValue, isDFUModeVM, isViewLoaded else { return }

            /// Force update of DFU state to display the ECID.
            handleDFUTransition(.enter)
        }
    }

    var automaticallyReconfiguresDisplay: Bool = true {
        didSet {
            guard #available(macOS 14.0, *) else { return }
            vmView.automaticallyReconfiguresDisplay = automaticallyReconfiguresDisplay
        }
    }

    var virtualMachine: VZVirtualMachine? {
        didSet {
            vmView.virtualMachine = virtualMachine
        }
    }

    private var canShowDFUView: Bool {
        #if DEBUG
        return ProcessInfo.isSwiftUIPreview || virtualMachine != nil
        #else
        return virtualMachine != nil
        #endif
    }

    var captureSystemKeysEnabled: Bool {
        get { vmView.capturesSystemKeysEnabled }
        set { vmView.capturesSystemKeysEnabled = newValue }
    }

    var eventDeliveryMask: VMEventDeliveryMask {
        get { vmView.eventDeliveryMask }
        set { vmView.eventDeliveryMask = newValue }
    }

    private lazy var vmView: VirtualBuddyVMView = {
        VirtualBuddyVMView(frame: .zero)
    }()
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        if #available(macOS 14.0, *) {
            vmView.automaticallyReconfiguresDisplay = automaticallyReconfiguresDisplay
        }

        vmView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vmView)

        NSLayoutConstraint.activate([
            vmView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vmView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vmView.topAnchor.constraint(equalTo: view.topAnchor),
            vmView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        
        guard let window = view.window else { return }
        
        window.makeFirstResponder(vmView)
        
        if isDFUModeVM { handleDFUTransition(.enter) }
    }

    enum DFUTransition: Hashable {
        case enter
        case exit
        case invalid

        init(wasInDFU: Bool, isInDFU: Bool) {
            if wasInDFU, !isInDFU {
                self = .exit
            } else if isInDFU, !wasInDFU {
                self = .enter
            } else {
                self = .invalid
            }
        }
    }

    private func handleDFUTransition(_ transition: DFUTransition) {
        switch transition {
        case .enter:
            showDFUView()
        case .exit:
            hideDFUView()
        case .invalid:
            break
        }
    }

    private var currentDFUView: NSView?

    private func showDFUView() {
        currentDFUView?.removeFromSuperview()

        guard canShowDFUView else { return }

        let dfuView = NSHostingView(rootView: DFUStatusView(ecid: vmECID))
        dfuView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dfuView)

        NSLayoutConstraint.activate([
            dfuView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            dfuView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            dfuView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 16),
            dfuView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16),
            dfuView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dfuView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func hideDFUView() {
        currentDFUView?.removeFromSuperview()
    }
}

struct DFUStatusView: View {
    var ecid: UInt64?

    @Environment(\.numberDisplayMode)
    private var numberDisplayMode

    var body: some View {
        VStack(spacing: 22) {
            VStack {
                Image(systemName: "cpu")
                    .imageScale(.large)
                Text("DFU Mode Active")
            }
            .font(.system(.largeTitle, design: .rounded))

            VStack(spacing: 8) {
                Text("This virtual machine is running in DFU mode.")
                    .font(.system(.title2, design: .rounded, weight: .medium))

                if let ecid {
                    HStack(spacing: 0) {
                        Text("ECID: ")
                            .font(.headline)

                        Text("\(ecid.formatted(mode: numberDisplayMode))")
                            .textSelection(.enabled)
                            .font(.headline.weight(.regular).monospaced())
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension VMEventDeliveryMask {
    var allowsMouseEvents: Bool { contains(.mouse) }
    var allowsKeyboardEvents: Bool { contains(.keyboard) }
}

final class VirtualBuddyVMView: VZVirtualMachineView {
    var eventDeliveryMask = VMEventDeliveryMask.all {
        didSet {
            guard eventDeliveryMask != oldValue else { return }

            if oldValue.allowsKeyboardEvents != eventDeliveryMask.allowsKeyboardEvents {
                if eventDeliveryMask.allowsKeyboardEvents {
                    window?.makeFirstResponder(self)
                } else {
                    window?.makeFirstResponder(nextResponder)
                }

                updateCaptureSystemKeysState()
            }
        }
    }

    var capturesSystemKeysEnabled: Bool = false {
        didSet {
            guard capturesSystemKeysEnabled != oldValue else { return }
            updateCaptureSystemKeysState()
        }
    }

    private func updateCaptureSystemKeysState() {
        /// We only want to enable capture system keys when the explicit setting is enabled and when keyboard event capture is also enabled.
        capturesSystemKeys = capturesSystemKeysEnabled && eventDeliveryMask.contains(.keyboard)

        UILog("eventDeliveryMask = \(eventDeliveryMask); capturesSystemKeysEnabled = \(capturesSystemKeysEnabled); capturesSystemKeys = \(capturesSystemKeys)")
    }

    override var acceptsFirstResponder: Bool {
        guard eventDeliveryMask.allowsKeyboardEvents else { return false }
        return super.acceptsFirstResponder
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard eventDeliveryMask.allowsMouseEvents else { return false }
        return super.acceptsFirstMouse(for: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard eventDeliveryMask.allowsMouseEvents else { return nil }
        return super.hitTest(point)
    }

    override func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool {
        guard eventDeliveryMask.allowsMouseEvents else { return false }
        return super.isMousePoint(point, in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.mouseDragged(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.mouseExited(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.mouseMoved(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.rightMouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.otherMouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.otherMouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.otherMouseUp(with: event)
    }

    override func updateTrackingAreas() {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.cursorUpdate(with: event)
    }

    override func resetCursorRects() {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.resetCursorRects()
    }

    override func discardCursorRects() {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.discardCursorRects()
    }

    override func addCursorRect(_ rect: NSRect, cursor object: NSCursor) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.addCursorRect(rect, cursor: object)
    }

    override func removeCursorRect(_ rect: NSRect, cursor object: NSCursor) {
        guard eventDeliveryMask.allowsMouseEvents else { return }
        super.removeCursorRect(rect, cursor: object)
    }

    override func keyDown(with event: NSEvent) {
        guard eventDeliveryMask.allowsKeyboardEvents else { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard eventDeliveryMask.allowsKeyboardEvents else { return }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard eventDeliveryMask.allowsKeyboardEvents else { return }
        super.flagsChanged(with: event)
    }
}

#if DEBUG
#Preview("VM View - DFU") {
    SwiftUIVMView(
        controllerState: .constant(.starting(nil)),
        captureSystemKeysEnabled: false,
        isDFUModeVM: true,
        vmECID: 7788022887768653863,
        automaticallyReconfiguresDisplay: .constant(false)
    )
}
#endif
