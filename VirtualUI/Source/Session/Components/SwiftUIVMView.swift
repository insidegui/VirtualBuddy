//
//  SwiftUIVMView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import Cocoa
import Virtualization
import VirtualCore

private extension EnvironmentValues {
    @Entry var virtualMachineInteractionDisabled = false
}

extension View {
    func virtualMachineInteractionDisabled(_ disabled: Bool = true) -> some View {
        environment(\.virtualMachineInteractionDisabled, disabled)
    }
}

struct SwiftUIVMView: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = VMViewController
    
    @Binding var controllerState: VMController.State
    let captureSystemKeys: Bool
    var isDFUModeVM: Bool
    var vmECID: UInt64?
    @Binding var automaticallyReconfiguresDisplay: Bool

    func makeNSViewController(context: Context) -> VMViewController {
        let controller = VMViewController()
        controller.vmECID = vmECID
        controller.isDFUModeVM = isDFUModeVM
        controller.captureSystemKeys = captureSystemKeys
        controller.automaticallyReconfiguresDisplay = automaticallyReconfiguresDisplay
        return controller
    }
    
    func updateNSViewController(_ nsViewController: VMViewController, context: Context) {
        nsViewController.automaticallyReconfiguresDisplay = automaticallyReconfiguresDisplay

        nsViewController.vmECID = vmECID
        nsViewController.isDFUModeVM = isDFUModeVM
        nsViewController.interactionDisabled = context.environment.virtualMachineInteractionDisabled

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

    var captureSystemKeys: Bool = false {
        didSet {
            guard captureSystemKeys != oldValue, isViewLoaded else { return }
            vmView.capturesSystemKeys = captureSystemKeys
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

    var interactionDisabled: Bool {
        get { vmView.isViewOnly }
        set { vmView.isViewOnly = newValue }
    }

    private lazy var vmView: VirtualBuddyVMView = {
        VirtualBuddyVMView(frame: .zero)
    }()
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        vmView.capturesSystemKeys = captureSystemKeys

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

final class VirtualBuddyVMView: VZVirtualMachineView {
    var isViewOnly = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isViewOnly else { return nil }
        return super.hitTest(point)
    }

    override func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool {
        guard !isViewOnly else { return false }
        return super.isMousePoint(point, in: rect)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard !isViewOnly else { return false }
        return super.acceptsFirstMouse(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isViewOnly else { return }
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool {
        guard !isViewOnly else { return false }
        return super.acceptsFirstResponder
    }

    override func updateTrackingAreas() {
        guard !isViewOnly else { return }
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !isViewOnly else { return }
        super.cursorUpdate(with: event)
    }

    override func resetCursorRects() {
        guard !isViewOnly else { return }
        super.resetCursorRects()
    }

    override func discardCursorRects() {
        guard !isViewOnly else { return }
        super.discardCursorRects()
    }

    override func addCursorRect(_ rect: NSRect, cursor object: NSCursor) {
        guard !isViewOnly else { return }
        super.addCursorRect(rect, cursor: object)
    }

    override func removeCursorRect(_ rect: NSRect, cursor object: NSCursor) {
        guard !isViewOnly else { return }
        super.removeCursorRect(rect, cursor: object)
    }
}

#if DEBUG
#Preview("VM View - DFU") {
    SwiftUIVMView(
        controllerState: .constant(.starting(nil)),
        captureSystemKeys: false,
        isDFUModeVM: true,
        vmECID: 7788022887768653863,
        automaticallyReconfiguresDisplay: .constant(false)
    )
}
#endif
