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
final class VMInstance: NSObject, ObservableObject {
    
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
    
    private var isLoadingNVRAM = false
    
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

    private func createMacPlaform() -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()

        macPlatform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: virtualMachineModel.auxiliaryStorageURL)

        if !FileManager.default.fileExists(atPath: virtualMachineModel.bundleURL.path) {
            fatalError("Missing Virtual Machine Bundle at \(virtualMachineModel.bundleURL.path). Run InstallationTool first to create it.")
        }

        // Retrieve the hardware model; you should save this value to disk during installation.
        guard let hardwareModelData = try? Data(contentsOf: virtualMachineModel.hardwareModelURL) else {
            fatalError("Failed to retrieve hardware model data.")
        }

        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            fatalError("Failed to create hardware model.")
        }

        if !hardwareModel.isSupported {
            fatalError("The hardware model is not supported on the current host")
        }
        macPlatform.hardwareModel = hardwareModel

        // Retrieve the machine identifier; you should save this value to disk during installation.
        guard let machineIdentifierData = try? Data(contentsOf: virtualMachineModel.machineIdentifierURL) else {
            fatalError("Failed to retrieve machine identifier data.")
        }

        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            fatalError("Failed to create machine identifier.")
        }
        macPlatform.machineIdentifier = machineIdentifier

        
        #warning("TODO: Store dev/prod fuse info in metadata and do entitlement check if not prod fused, throwing an error if no entitlement")
        if NSApp.hasEntitlement("com.apple.private.virtualization") {
            macPlatform._isProductionModeEnabled = false
        }
        
        return macPlatform
    }

    // MARK: Create the Virtual Machine Configuration and instantiate the Virtual Machine

    private func makeConfiguration() -> VZVirtualMachineConfiguration {
        let helper = MacOSVirtualMachineConfigurationHelper(vm: virtualMachineModel)
        let c = VZVirtualMachineConfiguration()

        c.platform = createMacPlaform()
        c.bootLoader = helper.createBootLoader()
        c.cpuCount = helper.computeCPUCount()
        c.memorySize = helper.computeMemorySize()
        c.graphicsDevices = [helper.createGraphicsDeviceConfiguration()]
        c.storageDevices = [
            helper.createBlockDeviceConfiguration()
        ]
        if let additionalBlockDevice = helper.createAdditionalBlockDevice() {
            c.storageDevices.append(additionalBlockDevice)
        }
        c.networkDevices = [
            helper.createNetworkDeviceConfiguration(),
        ]
        c.pointingDevices = [
            helper.createPointingDeviceConfiguration2()
        ]
        c.keyboards = [helper.createKeyboardConfiguration()]
        c.audioDevices = [helper.createAudioDeviceConfiguration()]
        c.serialPorts = [helper.serialConfiguration()]
        c.socketDevices = [helper.socketConfiguration()]
        
        return c
    }
    
    private func createVirtualMachine() throws {
        let config = makeConfiguration()

        do {
            try config.validate()
        } catch {
            logger.fault("Invalid configuration: \(String(describing: error))")
            
            throw Failure("Failed to validate configuration: \(String(describing: error))")
        }

        _virtualMachine = VZVirtualMachine(configuration: config)
        
        let vm = try virtualMachine
        
        if let attachment = config.serialPorts.first?.attachment as? VZFileHandleSerialPortAttachment,
           let readHandle = attachment.fileHandleForReading,
           let writeHandle = attachment.fileHandleForWriting
        {
            _wormhole = WormholeManager(with: vm, fileHandleForReading: readHandle, fileHandleForWriting: writeHandle)
        }
    }
    
    private var startOptions: _VZVirtualMachineStartOptions {
        let opts = _VZVirtualMachineStartOptions()
        opts.bootMacOSRecovery = options.bootInRecoveryMode
        return opts
    }
    
    private var hookingPoint: VBObjCHookingPoint?
    
    func startVM() async throws {
        try createVirtualMachine()
        
        let vm = try ensureVM()
        
        hookingPoint = VBObjCHookingPoint(vm: vm)

        vm.delegate = self
        
        hookingPoint?.hook()
        
        try await vm._start(with: startOptions)
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
    }
    
    func forceStop() async throws {
        let vm = try ensureVM()
        
        try await vm.stop()
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
    
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onVMStop(error) }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        DispatchQueue.main.async { self.onVMStop(nil) }
    }
    
    func virtualMachine(_ virtualMachine: VZVirtualMachine, networkDevice: VZNetworkDevice, attachmentWasDisconnectedWithError error: Error) {
        
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
