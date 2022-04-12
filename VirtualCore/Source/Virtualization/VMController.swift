//
//  VMController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/04/22.
//

import Cocoa
import Foundation
import Virtualization
import Combine
import OSLog

public struct VMSessionOptions: Hashable, Codable {
    public var bootInRecoveryMode = false
    public var captureSystemKeys = false
    
    public static let `default` = VMSessionOptions()
}

@MainActor
public final class VMController: ObservableObject {
    
    private let logger = Logger(subsystem: "codes.rambo.VirtualBuddy", category: String(describing: VMController.self))
    
    @Published
    public var options = VMSessionOptions.default
    
    public enum State {
        case idle
        case starting
        case running(VZVirtualMachine)
        case paused(VZVirtualMachine)
        case stopped(Error?)
    }
    
    @Published
    public private(set) var state = State.idle
    
    private(set) var virtualMachine: VZVirtualMachine?
    
    private var isLoadingNVRAM = false
    
    @Published
    public var virtualMachineModel: VBVirtualMachine {
        didSet {
            precondition(oldValue.id == virtualMachineModel.id, "Can't change the virtual machine identity after initializing the controller")
            
            if !isLoadingNVRAM, oldValue.NVRAM != virtualMachineModel.NVRAM {
                updateNVRAM()
            }
        }
    }
    
    public init(with vm: VBVirtualMachine) {
        self.virtualMachineModel = vm
        
        isLoadingNVRAM = true
        loadNVRAM()
        DispatchQueue.main.async { self.isLoadingNVRAM = false }
    }

    // MARK: Create the Mac Platform Configuration

    private func createMacPlaform() -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()

        let auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: virtualMachineModel.auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage

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

        return macPlatform
    }

    // MARK: Create the Virtual Machine Configuration and instantiate the Virtual Machine

    private var configuration: VZVirtualMachineConfiguration {
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
        c.networkDevices = [helper.createNetworkDeviceConfiguration()]
        c.pointingDevices = [helper.createPointingDeviceConfiguration()]
        c.keyboards = [helper.createKeyboardConfiguration()]
        c.audioDevices = [helper.createAudioDeviceConfiguration()]
        c._multiTouchDevices = [helper.createMultiTouchDeviceConfiguration()]
        
        return c
    }
    
    private func createVirtualMachine() {
        let config = configuration

        try! config.validate()

        virtualMachine = VZVirtualMachine(configuration: config)
    }
    
    private var vmDelegate: MacOSVirtualMachineDelegate?
    
    private var startOptions: _VZVirtualMachineStartOptions {
        let opts = _VZVirtualMachineStartOptions()
        opts.bootMacOSRecovery = options.bootInRecoveryMode
        return opts
    }
    
    private var hookingPoint: VBObjCHookingPoint?
    
    public func startVM() async throws {
        state = .starting
        
        let vm = try ensureVM()
        
        hookingPoint = VBObjCHookingPoint(vm: vm)
        
        vmDelegate = MacOSVirtualMachineDelegate(onVMStop: { [weak self] error in
            self?.state = .stopped(error)
        })
        
        vm.delegate = vmDelegate
        
        hookingPoint?.hook()
        
        try await vm._start(with: startOptions)
        
        state = .running(vm)
    }
    
    public func pause() async throws {
        let vm = try ensureVM()
        
        try await vm.pause()
        
        state = .paused(vm)
    }
    
    public func resume() async throws {
        let vm = try ensureVM()
        
        try await vm.resume()
        
        state = .running(vm)
    }
    
    public func stop() async throws {
        let vm = try ensureVM()
        
        try vm.requestStop()
        
        state = .stopped(nil)
    }
    
    public func forceStop() async throws {
        let vm = try ensureVM()
        
        try await vm.stop()
        
        state = .stopped(nil)
    }
    
    private func ensureVM() throws -> VZVirtualMachine {
        guard let vm = virtualMachine else {
            let e = CocoaError(.executableLoad)
            
            state = .stopped(e)
            
            throw e
        }
        
        return vm
    }
    
    /// Called when the `VBVirtualMachine` has updated NVRAM variables.
    private func updateNVRAM() {
        logger.debug(#function)
        
        do {
            try virtualMachineModel.NVRAM.forEach { variable in
                try configuration.updateNVRAM(variable)
            }
        } catch {
            logger.fault("Failed to write NVRAM: \(String(describing: error), privacy: .public)")
        }
    }
    
    private func loadNVRAM() {
        do {
            let vars = try configuration.fetchNVRAMVariables()
            self.virtualMachineModel.NVRAM = vars
        } catch {
            logger.fault("Failed to read NVRAM: \(String(describing: error), privacy: .public)")
        }
    }
    
}

public extension VMController {
    
    var canStart: Bool {
        switch state {
        case .idle, .stopped:
            return true
        default:
            return false
        }
    }
    
    var canResume: Bool {
        switch state {
        case .paused:
            return true
        default:
            return false
        }
    }
    
    var canPause: Bool {
        switch state {
        case .running:
            return true
        default:
            return false
        }
    }
    
}
