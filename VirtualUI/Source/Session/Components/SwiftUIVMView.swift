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

struct SwiftUIVMView: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = VMViewController
    
    @Binding var controllerState: VMController.State
    let captureSystemKeys: Bool
    var isDFUModeVM: Bool
    var vmECID: UInt64?
    @Binding var automaticallyReconfiguresDisplay: Bool
    let screenshotSubject: VMScreenshotter.Subject

    func makeNSViewController(context: Context) -> VMViewController {
        let controller = VMViewController(screenshotSubject: screenshotSubject)
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

    let screenshotSubject: VMScreenshotter.Subject

    init(screenshotSubject: VMScreenshotter.Subject) {
        self.screenshotSubject = screenshotSubject

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
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

    private lazy var vmView: VZVirtualMachineView = {
        VZVirtualMachineView(frame: .zero)
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

    private lazy var screenshotter: VMScreenshotter = {
        VMScreenshotter(interval: 15, screenshotSubject: screenshotSubject)
    }()

    override func viewDidAppear() {
        super.viewDidAppear()
        
        guard let window = view.window else { return }
        
        window.makeFirstResponder(vmView)
        
        activateScreenshotterIfNeeded()

        if isDFUModeVM { handleDFUTransition(.enter) }
    }

    private func activateScreenshotterIfNeeded() {
        /// Screenshotter is not useful when the VM is in DFU mode.
        guard !isDFUModeVM, isViewLoaded else { return }

        screenshotter.activate(with: view, vm: vmView.virtualMachine)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        screenshotter.invalidate()
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
            screenshotter.invalidate()
        case .exit:
            hideDFUView()
            activateScreenshotterIfNeeded()
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

#if DEBUG
#Preview("VM View - DFU") {
    SwiftUIVMView(
        controllerState: .constant(.starting),
        captureSystemKeys: false,
        isDFUModeVM: true,
        vmECID: 7788022887768653863,
        automaticallyReconfiguresDisplay: .constant(false),
        screenshotSubject: .init()
    )
}
#endif
