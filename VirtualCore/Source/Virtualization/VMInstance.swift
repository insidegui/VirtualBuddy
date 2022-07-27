//
//  VMInstance.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 12/04/22.
//

import Cocoa
import Foundation
import Virtualization
import Combine
import OSLog
import VirtualWormhole

@MainActor
public final class VMInstance: NSObject, ObservableObject {

    private let library = VMLibraryController.shared
    
    private lazy var logger = Logger(for: Self.self)
    
    var options = VMSessionOptions.default

    private var _virtualMachine: VZVirtualMachine?
    
    private var _wormhole: WormholeManager?
    
    var virtualMachine: VZVirtualMachine {
        get throws {
            guard let vm = _virtualMachine else {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
            
            return vm
        }
    }
    
    var wormhole: WormholeManager {
        get throws {
            guard let wh = _wormhole else {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
            
            return wh
        }
    }
    
    var virtualMachineModel: VBVirtualMachine {
        didSet {
            precondition(oldValue.id == virtualMachineModel.id, "Can't change the virtual machine identity after initializing the controller")
        }
    }
    
    var onVMStop: (Error?) -> Void = { _ in }
    
    init(with vm: VBVirtualMachine, onVMStop: @escaping (Error?) -> Void) {
        self.virtualMachineModel = vm
        self.onVMStop = onVMStop
    }
    
    // MARK: Create the Mac Platform Configuration

    private static func loadRestoreImage(from url: URL) async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { continuation in
            VZMacOSRestoreImage.load(from: url) { result in
                continuation.resume(with: result)
            }
        }
    }

    public static func createMacPlaform(for model: VBVirtualMachine, installImageURL: URL?) async throws -> VZMacPlatformConfiguration {
        let image: VZMacOSRestoreImage?

        if let installImageURL = installImageURL {
            image = try await loadRestoreImage(from: installImageURL)
        } else {
            image = nil
        }

        let macPlatform = VZMacPlatformConfiguration()

        let hardwareModel = try model.fetchOrGenerateHardwareModel(with: image)

        macPlatform.hardwareModel = hardwareModel

        macPlatform.auxiliaryStorage = try model.fetchOrGenerateAuxiliaryStorage(hardwareModel: hardwareModel)

        macPlatform.machineIdentifier = try model.fetchOrGenerateMachineIdentifier()

        return macPlatform
    }

    // MARK: Create the Virtual Machine Configuration and instantiate the Virtual Machine

    public static func makeConfiguration(for model: VBVirtualMachine, installImageURL: URL? = nil) async throws -> VZVirtualMachineConfiguration {
        let helper = MacOSVirtualMachineConfigurationHelper(vm: model)
        let c = VZVirtualMachineConfiguration()

        c.platform = try await Self.createMacPlaform(for: model, installImageURL: installImageURL)
        c.bootLoader = helper.createBootLoader()
        c.cpuCount = model.configuration.hardware.cpuCount
        c.memorySize = model.configuration.hardware.memorySize
        c.graphicsDevices = model.configuration.vzGraphicsDevices
        c.networkDevices = try model.configuration.vzNetworkDevices
        c.pointingDevices = try model.configuration.vzPointingDevices
        c.keyboards = [helper.createKeyboardConfiguration()]
        c.audioDevices = model.configuration.vzAudioDevices
        c.directorySharingDevices = try model.configuration.vzSharedFoldersFileSystemDevices
        
        if #available(macOS 13.0, *), let clipboardSync = model.configuration.vzClipboardSyncDevice {
            c.consoleDevices = [clipboardSync]
        }
        
        let bootDevice = try await helper.createBootBlockDevice()
        let additionalBlockDevices = try await helper.createAdditionalBlockDevices()

        c.storageDevices = [bootDevice] + additionalBlockDevices
        
        return c
    }
    
    private func createVirtualMachine() async throws {
        let config = try await Self.makeConfiguration(for: virtualMachineModel)

        do {
            try config.validate()
        } catch {
            logger.fault("Invalid configuration: \(String(describing: error))")
            
            throw Failure("Failed to validate configuration: \(String(describing: error))")
        }

        _virtualMachine = VZVirtualMachine(configuration: config)
        
        _wormhole = WormholeManager(for: .host)
    }
    
    private var hookingPoint: VBObjCHookingPoint?
    
    func startVM() async throws {
        try await createVirtualMachine()
        
        let vm = try ensureVM()
        
        hookingPoint = VBObjCHookingPoint(vm: vm)

        vm.delegate = self
        
        hookingPoint?.hook()

        if #available(macOS 13, *) {
            let opts = VZMacOSVirtualMachineStartOptions()
            opts.startUpFromMacOSRecovery = options.bootInRecoveryMode
            try await vm.start(options: opts)
        } else {
            let opts = _VZVirtualMachineStartOptions()
            opts.bootMacOSRecovery = options.bootInRecoveryMode
            try await vm._start(with: opts)
        }

        VMLibraryController.shared.bootedMachineIdentifiers.insert(self.virtualMachineModel.id)
    }
    
    func pause() async throws {
        let vm = try ensureVM()
        
        try await vm.pause()
    }
    
    func resume() async throws {
        let vm = try ensureVM()
        
        try await vm.resume()
    }
    
    func stop() async throws {
        let vm = try ensureVM()
        
        try vm.requestStop()

        library.bootedMachineIdentifiers.remove(virtualMachineModel.id)
    }
    
    func forceStop() async throws {
        let vm = try ensureVM()
        
        try await vm.stop()

        library.bootedMachineIdentifiers.remove(virtualMachineModel.id)
    }
    
    private func ensureVM() throws -> VZVirtualMachine {
        guard let vm = _virtualMachine else {
            let e = CocoaError(.executableLoad)
            
            DispatchQueue.main.async {
                self.onVMStop(e)
            }
            
            throw e
        }
        
        return vm
    }
    
    func takeScreenshot() async throws -> NSImage {
        guard let fb = _virtualMachine?._graphicsDevices.first?.framebuffers().first else {
            throw Failure("Couldn't get framebuffer")
        }
        
        let screenshot = try await fb.takeScreenshot()
        
        return screenshot
    }
    
}

// MARK: - VZVirtualMachineDelegate

extension VMInstance: VZVirtualMachineDelegate {
    
    public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        logger.error("Stopped with error: \(String(describing: error), privacy: .public)")

        DispatchQueue.main.async { [self] in
            library.bootedMachineIdentifiers.remove(virtualMachineModel.id)
            
            _wormhole = nil
            
            onVMStop(error)
        }
    }

    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        DispatchQueue.main.async { [self] in
            library.bootedMachineIdentifiers.remove(virtualMachineModel.id)

            _wormhole = nil
            
            onVMStop(nil)
        }
    }
    
    public func virtualMachine(_ virtualMachine: VZVirtualMachine, networkDevice: VZNetworkDevice, attachmentWasDisconnectedWithError error: Error) {
        
    }
    
}

extension NSApplication {
    
    func entitlementValue<V>(for entitlement: String) -> V? {
        guard let task = SecTaskCreateFromSelf(nil) else {
            assertionFailure("SecTaskCreateFromSelf returned nil")
            return nil
        }
        
        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) as? V
    }
    
    func hasEntitlement(_ entitlement: String) -> Bool {
        entitlementValue(for: entitlement) == true
    }
    
}
