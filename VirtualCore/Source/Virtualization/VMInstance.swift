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

        let hardwareModel: VZMacHardwareModel

        if FileManager.default.fileExists(atPath: model.hardwareModelURL.path) {
            guard let hardwareModelData = try? Data(contentsOf: model.hardwareModelURL) else {
                throw Failure("Failed to retrieve hardware model data.")
            }

            guard let hw = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
                throw Failure("Failed to create hardware model.")
            }

            hardwareModel = hw
        } else {
            guard let image = image else {
                throw Failure("Hardware model data doesn't exist, but a restore image was not provided to create the initial data.")
            }

            guard let hw = image.mostFeaturefulSupportedConfiguration?.hardwareModel else {
                throw Failure("Failed to obtain hardware model from restore image")
            }

            hardwareModel = hw

            try hw.dataRepresentation.write(to: model.hardwareModelURL)
        }

        guard hardwareModel.isSupported else {
            throw Failure("The hardware model is not supported on the current host")
        }

        macPlatform.hardwareModel = hardwareModel

        if FileManager.default.fileExists(atPath: model.auxiliaryStorageURL.path) {
            macPlatform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: model.auxiliaryStorageURL)
        } else {
            macPlatform.auxiliaryStorage = try VZMacAuxiliaryStorage(
                creatingStorageAt: model.auxiliaryStorageURL,
                hardwareModel: hardwareModel
            )
        }

        let machineIdentifier: VZMacMachineIdentifier

        if FileManager.default.fileExists(atPath: model.machineIdentifierURL.path) {
            guard let machineIdentifierData = try? Data(contentsOf: model.machineIdentifierURL) else {
                throw Failure("Failed to retrieve machine identifier data.")
            }

            guard let mid = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
                throw Failure("Failed to create machine identifier.")
            }

            machineIdentifier = mid
        } else {
            machineIdentifier = VZMacMachineIdentifier()

            try machineIdentifier.dataRepresentation.write(to: model.machineIdentifierURL)
        }

        macPlatform.machineIdentifier = machineIdentifier
        
        #warning("TODO: Store dev/prod fuse info in metadata and do entitlement check if not prod fused, throwing an error if no entitlement")
        if NSApp.hasEntitlement("com.apple.private.virtualization") {
            macPlatform._isProductionModeEnabled = false
        }
        
        return macPlatform
    }

    // MARK: Create the Virtual Machine Configuration and instantiate the Virtual Machine

    public static func makeConfiguration(for model: VBVirtualMachine, installImageURL: URL? = nil) async throws -> VZVirtualMachineConfiguration {
        let helper = MacOSVirtualMachineConfigurationHelper(vm: model)
        let c = VZVirtualMachineConfiguration()

        c.platform = try await Self.createMacPlaform(for: model, installImageURL: installImageURL)
        c.bootLoader = helper.createBootLoader()
        c.cpuCount = helper.computeCPUCount()
        c.memorySize = helper.computeMemorySize()
        c.graphicsDevices = [helper.createGraphicsDeviceConfiguration()]
        c.storageDevices = [
            try helper.createBlockDeviceConfiguration()
        ]
        if let additionalBlockDevice = try helper.createAdditionalBlockDevice() {
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
    
    private var startOptions: _VZVirtualMachineStartOptions {
        let opts = _VZVirtualMachineStartOptions()
        opts.bootMacOSRecovery = options.bootInRecoveryMode
        return opts
    }
    
    private var hookingPoint: VBObjCHookingPoint?
    
    func startVM() async throws {
        try await createVirtualMachine()
        
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
    
    public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self._wormhole = nil
            
            self.onVMStop(error)
        }
    }

    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        DispatchQueue.main.async {
            self._wormhole = nil
            
            self.onVMStop(nil)
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
