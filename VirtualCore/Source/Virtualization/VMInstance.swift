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
    
//    let wormhole: WormholeManager = .sharedHost
    
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

        let vm = VZVirtualMachine(configuration: config)

        _virtualMachine = vm
    }

    private func setupWormhole(for config: VZVirtualMachineConfiguration) async {
        guard virtualMachineModel.configuration.systemType == .mac else { return }

//        wormhole.activate()

        let socket = VZVirtioSocketDeviceConfiguration()
        config.socketDevices = [socket]
    }

    private var guestClient: Any?

    private func activateWormhole(with vm: VZVirtualMachine) {
//        await wormhole.addServiceListeners(to: vm, peerID: virtualMachineModel.wormholeID)
        guard let socketDevice = vm.socketDevices.first as? VZVirtioSocketDevice else {
            assertionFailure("Expected socket device")
            return
        }

        guard #available(macOS 13.0, *) else { return }

        let client = WHGuestClient(device: socketDevice, port: 6789, remote: true)
        self.guestClient = client

        client.activate()
    }

    private lazy var guestIOTasks = [Task<Void, Never>]()

    public func streamGuestNotifications() {
        logger.debug(#function)
        
//        let notificationNames: Set<String> = [
//            "com.apple.shieldWindowRaised",
//            "com.apple.shieldWindowLowered"
//        ]
//
//        let task = Task {
//            do {
//                for await notification in try await wormhole.darwinNotifications(matching: notificationNames, from: virtualMachineModel.wormholeID) {
//                    if notification == "com.apple.shieldWindowRaised" {
//                        logger.debug("🔒 Guest locked")
//                    } else if notification == "com.apple.shieldWindowLowered" {
//                        logger.debug("🔓 Guest unlocked")
//                    }
//                }
//            } catch {
//                logger.error("Error subscribing to Darwin notifications: \(error, privacy: .public)")
//            }
//        }
//        guestIOTasks.append(task)
    }
    
    func startVM() async throws {
        try await createVirtualMachine()
        
        let vm = try ensureVM()

        vm.delegate = self

        try await vm.start(options: startOptions)

        VMLibraryController.shared.bootedMachineIdentifiers.insert(self.virtualMachineModel.id)

        activateWormhole(with: vm)
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

    private var testTask: Task<Void, Never>?
    private var connection: VZVirtioSocketConnection?
    private var socketHandle: FileHandle?

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
//                await wormhole.unregister(virtualMachineModel.wormholeID)
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
//
//private final class TestSocketConnection {
//
//    let device: VZVirtioSocketDevice
//
//    init(device: VZVirtioSocketDevice) {
//        self.device = device
//    }
//
//    private var internalTask: Task<Void, Never>?
//
//    func activate() {
//        guard internalTask == nil else { return }
//        
//        print("-> Activate for \(device)")
//
//        internalTask = Task {
//            await _activate()
//        }
//    }
//
//    private var isConnected = false
//    private var connection: VZVirtioSocketConnection!
//
//    private func _activate() async {
//        while !isConnected {
//            guard !Task.isCancelled else { return }
//
//            do {
//                let connection = try await Task { @MainActor in try await device.connect(toPort: 6789) }.value
//
//                self.connection = connection
//
//                var addr = sockaddr_vm()
//
//                let addrPtr = withUnsafeMutableBytes(of: &addr) { ptr in
//                    ptr.assumingMemoryBound(to: sockaddr.self).baseAddress!
//                }
//                var len = socklen_t(MemoryLayout<sockaddr_vm>.size)
//
//                let res = getpeername(connection.fileDescriptor, addrPtr, &len)
//                if res < 0 {
//                    print("-> getpeername failed with errno \(errno)")
//                }
//
//                print("-> SOCKET CONNECTED (destinationPort: \(connection.destinationPort), sourcePort: \(connection.sourcePort), fileDescriptor: \(connection.fileDescriptor), svm_port: \(addr.svm_port), svm_cid: \(addr.svm_cid))")
//
//                isConnected = true
//            } catch {
//                print("-> Socket connection failed: \(error)")
//
//                await Task.yield()
//                try? await Task.sleep(nanoseconds: 5_000_000_000)
//            }
//        }
//
//        if let connection { await _communicate(on: connection) }
//    }
//
//    private var counter: UInt8 = 0
//
//    private func _communicate(on connection: VZVirtioSocketConnection) async {
//        let handle = FileHandle(fileDescriptor: connection.fileDescriptor)
//
//        while isConnected {
//            try? await Task.sleep(nanoseconds: 2_000_000_000)
//
//            guard !Task.isCancelled else { return }
//
//            print("-> Sending stuff on socket")
//
//            do {
//                try handle.write(contentsOf: Data([counter]))
//
//                counter += 1
//
//                if counter >= UInt8.max {
//                    counter = 0
//                }
//            } catch {
//                print("-> Socket write failed: \(error)")
//                isConnected = false
//
//                await reset()
//            }
//        }
//    }
//
//    private func reset() async {
//        print("-> Reset")
//
//        await MainActor.run { connection?.close() }
//
//        self.connection = nil
//        self.isConnected = false
//        self.internalTask?.cancel()
//        self.internalTask = nil
//        self.counter = 0
//
//        try? await Task.sleep(nanoseconds: 500_000_000)
//
//        activate()
//    }
//
//}
