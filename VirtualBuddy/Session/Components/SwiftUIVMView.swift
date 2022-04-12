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

final class SwiftUIVMView: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = VMViewController
    
    @Binding var controllerState: VMController.State
    
    init(controllerState: Binding<VMController.State>) {
        self._controllerState = controllerState
    }
    
    func makeNSViewController(context: Context) -> VMViewController {
        VMViewController()
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

    convenience init() {
        self.init(nibName: nil, bundle: nil)
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
        view = VMContainerView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        vmView.capturesSystemKeys = false
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
        
        print("viewDidAppear")
        
        guard let window = view.window else { return }
        
        let result = window.makeFirstResponder(vmView)
        
        print("makeFirstResponder = \(result)")
    }
    
}

fileprivate final class VMContainerView: NSView {
    
    override var acceptsFirstResponder: Bool { true }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override var canBecomeKeyView: Bool { true }
    
}
