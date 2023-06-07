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
    let screenshotSubject: VMScreenshotter.Subject

    func makeNSViewController(context: Context) -> VMViewController {
        let controller = VMViewController(screenshotSubject: screenshotSubject)
        controller.captureSystemKeys = captureSystemKeys
        return controller
    }
    
    func updateNSViewController(_ nsViewController: VMViewController, context: Context) {
        if case .running(let vm) = controllerState {
            nsViewController.virtualMachine = vm
        } else {
            nsViewController.virtualMachine = nil
        }
    }
    
}

final class VMViewController: NSViewController {
    
    var captureSystemKeys: Bool = false {
        didSet {
            guard captureSystemKeys != oldValue, isViewLoaded else { return }
            vmView.capturesSystemKeys = captureSystemKeys
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
    
    private lazy var vmView: VZVirtualMachineView = {
        VZVirtualMachineView(frame: .zero)
    }()
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        vmView.capturesSystemKeys = captureSystemKeys
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
        
        screenshotter.activate(with: view)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        screenshotter.invalidate()
    }

}
