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
    
    var virtualMachine: VZVirtualMachine {
        get throws {
            guard let vm = _virtualMachine else {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
            
            return vm
        }
    }
    
    let wormhole: WormholeManager = .sharedHost
    
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

    public static func createMacPlatform(for model: VBVirtualMachine, installImageURL: URL?) async throws -> VZMacPlatformConfiguration {
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

    @available(macOS 13.0, *)
    public static func createGenericPlatform(for model: VBVirtualMachine, installImageURL: URL?) async throws -> VZGenericPlatformConfiguration {
        let genericPlatform = VZGenericPlatformConfiguration()
        return genericPlatform
    }

    // MARK: Create the Virtual Machine Configuration and instantiate the Virtual Machine

    public static func makeConfiguration(for model: VBVirtualMachine, installImageURL: URL? = nil) async throws -> VZVirtualMachineConfiguration {
        let helper: VirtualMachineConfigurationHelper
        let platform: VZPlatformConfiguration
        let installDevice: [VZStorageDeviceConfiguration]
        switch model.configuration.systemType {
        case .mac:
            helper = MacOSVirtualMachineConfigurationHelper(vm: model)
            platform = try await Self.createMacPlatform(for: model, installImageURL: installImageURL)
            installDevice = []
        case .linux:
            helper = LinuxVirtualMachineConfigurationHelper(vm: model)
            platform = try await Self.createGenericPlatform(for: model, installImageURL: nil)
            if let installImageURL {
                installDevice = [try helper.createInstallDevice(installImageURL: installImageURL)]
            } else {
                installDevice = []
            }
        }
        let c = VZVirtualMachineConfiguration()

        c.platform = platform
        c.bootLoader = try helper.createBootLoader()
        c.cpuCount = model.configuration.hardware.cpuCount
        c.memorySize = model.configuration.hardware.memorySize
        c.graphicsDevices = helper.createGraphicsDevices()
        c.networkDevices = try model.configuration.vzNetworkDevices
        c.pointingDevices = try model.configuration.vzPointingDevices
        c.keyboards = [helper.createKeyboardConfiguration()]
        c.entropyDevices = helper.createEntropyDevices()
        c.audioDevices = model.configuration.vzAudioDevices
        c.directorySharingDevices = try model.configuration.vzSharedFoldersFileSystemDevices
        if let spiceAgent = helper.createSpiceAgentConsoleDeviceConfiguration() {
            c.consoleDevices = [spiceAgent]
        }

        let bootDevice = try await helper.createBootBlockDevice()
        let additionalBlockDevices = try await helper.createAdditionalBlockDevices()

        c.storageDevices = installDevice + [bootDevice] + additionalBlockDevices
        
        return c
    }
    
    private func createVirtualMachine() async throws {
        let installImage: URL?
        if options.bootOnInstallDevice {
            installImage = virtualMachineModel.metadata.installImageURL
        } else {
            installImage = nil
        }
        let config = try await Self.makeConfiguration(for: virtualMachineModel, installImageURL: installImage) // add install iso here for linux (hack)

        await setupWormhole(for: config)

        do {
            try config.validate()
        } catch {
            logger.fault("Invalid configuration: \(String(describing: error))")
            
            throw Failure("Failed to validate configuration: \(String(describing: error))")
        }

        _virtualMachine = VZVirtualMachine(configuration: config)
    }

    private func setupWormhole(for config: VZVirtualMachineConfiguration) async {
        guard virtualMachineModel.configuration.systemType == .mac else { return }

        wormhole.activate()

        let guestPort = VZVirtioConsoleDeviceSerialPortConfiguration()

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        let inputHandle = inputPipe.fileHandleForWriting
        let outputHandle = outputPipe.fileHandleForReading

        guestPort.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: outputHandle,
            fileHandleForWriting: inputHandle
        )

        config.serialPorts = [guestPort]

        await wormhole.register(
            input: inputPipe.fileHandleForReading,
            output: outputPipe.fileHandleForWriting,
            for: virtualMachineModel.wormholeID
        )

        streamGuestNotifications()
    }

    private lazy var guestIOTasks = [Task<Void, Never>]()

    public func streamGuestNotifications() {
        logger.debug(#function)
        
        let notificationNames: Set<String> = [
            "com.apple.shieldWindowRaised",
            "com.apple.shieldWindowLowered"
        ]

        let task = Task {
            do {
                for await notification in try await wormhole.darwinNotifications(matching: notificationNames, from: virtualMachineModel.wormholeID) {
                    if notification == "com.apple.shieldWindowRaised" {
                        logger.debug("🔒 Guest locked")
                    } else if notification == "com.apple.shieldWindowLowered" {
                        logger.debug("🔓 Guest unlocked")
                    }
                }
            } catch {
                logger.error("Error subscribing to Darwin notifications: \(error, privacy: .public)")
            }
        }
        guestIOTasks.append(task)
    }
    
    func startVM() async throws {
        try await bootstrap()

        let vm = try ensureVM()

        try await vm.start(options: startOptions)
    }

    private func bootstrap() async throws {
        try await createVirtualMachine()

        let vm = try ensureVM()

        vm.delegate = self

        VMLibraryController.shared.bootedMachineIdentifiers.insert(self.virtualMachineModel.id)
    }

    @available(macOS 13, *)
    private var startOptions: VZVirtualMachineStartOptions {
        switch virtualMachineModel.configuration.systemType {
        case .mac:
            let opts = VZMacOSVirtualMachineStartOptions()
            opts.startUpFromMacOSRecovery = options.bootInRecoveryMode
            return opts
        case .linux:
            return VZVirtualMachineStartOptions()
        }
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

        library.bootedMachineIdentifiers.remove(virtualMachineModel.id)
    }

    @available(macOS 14.0, *)
    func saveState() async throws {
        logger.debug("Pausing to save state")

        try await pause()

        logger.debug("VM paused, requesting state save")
        
        let vm = try ensureVM()

        let metadata = VBSavedStateMetadata(model: virtualMachineModel)

        let packageURL = try virtualMachineModel.createSavedStatePackage(in: library)
        let stateFileURL = virtualMachineModel.savedStateDataFileURL(in: packageURL)
        let metadataFileURL = virtualMachineModel.savedStateInfoFileURL(in: packageURL)

        logger.debug("VM state package will be written to \(packageURL.path)")

        do {
            try await vm.saveMachineStateTo(url: stateFileURL)

            logger.log("VM state saved to \(stateFileURL.path)")

            let encodedMetadata = try PropertyListEncoder.virtualBuddy.encode(metadata)

            try encodedMetadata.write(to: metadataFileURL)
        } catch {
            try? FileManager.default.removeItem(at: packageURL)

            logger.error("VM state save failed: \(error, privacy: .public)")

            throw error
        }
    }

    @available(macOS 14.0, *)
    func restoreState(from fileURL: URL) async throws {
        if _virtualMachine == nil {
            try await bootstrap()
        }

        let vm = try ensureVM()

        logger.debug("Restoring state from \(fileURL.path)")

        do {
            try await vm.restoreMachineStateFrom(url: fileURL)

            logger.log("Successfully restored state from \(fileURL.path), resuming VM")

            try await resume()
        } catch {
            logger.error("VM state restoration failed: \(error, privacy: .public). State file: \(fileURL.path)")

            throw error
        }
    }

    private func ensureVM() throws -> VZVirtualMachine {
        guard let vm = _virtualMachine else {
            let e = Failure("The virtual machine instance is not available.")

            DispatchQueue.main.async {
                self.onVMStop(e)
            }
            
            throw e
        }
        
        return vm
    }
    
}

// MARK: - VZVirtualMachineDelegate

extension VMInstance: VZVirtualMachineDelegate {
    
    public func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        handleGuestStopped(with: error)
    }

    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        handleGuestStopped(with: nil)
    }
    
    public func virtualMachine(_ virtualMachine: VZVirtualMachine, networkDevice: VZNetworkDevice, attachmentWasDisconnectedWithError error: Error) {
        
    }

    private func handleGuestStopped(with error: Error?) {
        guestIOTasks.forEach { $0.cancel() }
        guestIOTasks.removeAll()

        if let error {
            logger.error("Guest stopped with error: \(String(describing: error), privacy: .public)")
        } else {
            logger.debug("Guest stopped")
        }

        DispatchQueue.main.async { [self] in
            library.bootedMachineIdentifiers.remove(virtualMachineModel.id)

            Task {
                await wormhole.unregister(virtualMachineModel.wormholeID)
            }

            onVMStop(error)
        }
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

private extension VBVirtualMachine {
    /// ``VBVirtualMachine/id`` uses the VM's filesystem URL,
    /// but that looks ugly in logs and whatnot, so this returns a cleaned up version.
    var wormholeID: WHPeerID {
        let cleanID = URL(fileURLWithPath: id)
            .deletingPathExtension()
            .lastPathComponent
        return cleanID.removingPercentEncoding ?? cleanID
    }
}
