//
//  VMInstance.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 12/04/22.
//

import Cocoa
import Foundation
@preconcurrency import Virtualization
import Combine
import OSLog
import VirtualWormhole
@_exported import VirtualMessaging
@_exported import MessageRouter

@MainActor
public final class VMInstance: NSObject, ObservableObject {

    private let library: VMLibraryController

    private let logger: Logger

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
    
    init(with vm: VBVirtualMachine, library: VMLibraryController, onVMStop: @escaping (Error?) -> Void) {
        self.virtualMachineModel = vm
        self.library = library
        self.onVMStop = onVMStop
        self.logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "VMInstance(\(vm.name))")
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
        if #available(macOS 15.0, *) {
            c.usbControllers = helper.createUSBControllers()
        }

        let bootDevice = try await helper.createBootBlockDevice()
        let additionalBlockDevices = try await helper.createAdditionalBlockDevices()

        c.storageDevices = installDevice + [bootDevice] + additionalBlockDevices

        let socket = VZVirtioSocketDeviceConfiguration()
        c.socketDevices = [socket]

        return c
    }
    
    private func createVirtualMachine() async throws {
        logger.debug(#function)

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

            logger.info("Configuration validated")
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

    private var socket: GuestSocketConnection?

    func startVM() async throws {
        try await bootstrap()

        let vm = try ensureVM()

        try await vm.start(options: startOptions)

        socket = GuestSocketConnection(vm: vm)
        socket?.activate()

        #if DEBUG
        VBDebugUtil.debugVirtualMachine(afterStart: vm)
        #endif
    }

    private func bootstrap() async throws {
        try await createVirtualMachine()

        let vm = try ensureVM()

        vm.delegate = self

        library.bootedMachineIdentifiers.insert(self.virtualMachineModel.id)

        #if DEBUG
        VBDebugUtil.debugVirtualMachine(beforeStart: vm)
        #endif
    }

    @available(macOS 13, *)
    private var startOptions: VZVirtualMachineStartOptions {
        switch virtualMachineModel.configuration.systemType {
        case .mac:
            return VZMacOSVirtualMachineStartOptions(options: options)
        case .linux:
            return VZVirtualMachineStartOptions()
        }
    }
    
    func pause() async throws {
        logger.debug(#function)

        let vm = try ensureVM()
        
        try await vm.pause()
    }
    
    func resume() async throws {
        logger.debug(#function)

        let vm = try ensureVM()
        
        try await vm.resume()
    }
    
    func stop() async throws {
        logger.debug(#function)

        let vm = try ensureVM()
        
        try vm.requestStop()
    }
    
    func forceStop() async throws {
        logger.debug(#function)

        let vm = try ensureVM()
        
        try await vm.stop()

        library.bootedMachineIdentifiers.remove(virtualMachineModel.id)
    }

    @available(macOS 14.0, *)
    @discardableResult
    func saveState(snapshotName name: String) async throws -> VBSavedStatePackage {
        logger.debug(#function)

        let vm = try ensureVM()

        logger.debug("Collecting screenshot for saved state")

        let screenshot: NSImage?
        do {
            screenshot = try await NSImage.screenshot(from: vm)
        } catch {
            screenshot = nil

            logger.warning("Error collecting screenshot for saved state: \(error, privacy: .public)")
        }

        logger.debug("Pausing to save state")

        try await pause()

        logger.debug("VM paused, requesting state save")

        let package = try virtualMachineModel.createSavedStatePackage(in: library, snapshotName: name)

        logger.debug("VM state package will be written to \(package.url.path)")

        package.screenshot = screenshot

        do {
            try await vm.saveMachineStateTo(url: package.dataFileURL)

            logger.log("VM state saved to \(package.dataFileURL.path)")

            return package
        } catch {
            try? FileManager.default.removeItem(at: package.url)

            logger.error("VM state save failed: \(error, privacy: .public)")

            throw error
        }
    }

    @available(macOS 14.0, *)
    func restoreState(from package: VBSavedStatePackage, updateHandler: (_ vm: VZVirtualMachine, _ package: VBSavedStatePackage) async -> Void) async throws {
        logger.debug("Restore state requested with package \(package.url.path)")

        try package.validate(for: virtualMachineModel)

        if _virtualMachine == nil {
            logger.debug("Bootstrapping VM for state restoration")

            try await bootstrap()
        }

        let vm = try ensureVM()

        await updateHandler(vm, package)

        logger.debug("Restoring state from \(package.dataFileURL.path)")

        do {
            try await vm.restoreMachineStateFrom(url: package.dataFileURL)

            logger.log("Successfully restored state from \(package.dataFileURL.path), resuming VM")

            try await resume()

            #if DEBUG
            VBDebugUtil.debugVirtualMachine(afterStart: vm)
            #endif
        } catch {
            logger.error("VM state restoration failed: \(error, privacy: .public). State file: \(package.dataFileURL.path)")

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
        socket?.invalidate()
        socket = nil

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

extension VZMacOSVirtualMachineStartOptions {
    convenience init(options: VMSessionOptions) {
        self.init()

        startUpFromMacOSRecovery = options.bootInRecoveryMode

        if options.bootInDFUMode,
           VBMacConfiguration.appBuildAllowsDFUMode,
           self.responds(to: NSSelectorFromString("_setForceDFU:"))
        {
            _forceDFU = true
            startUpFromMacOSRecovery = false
        }
    }
}

final class GuestSocketConnection {

    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: String(describing: GuestSocketConnection.self))

    weak var vm: VZVirtualMachine?

    init(vm: VZVirtualMachine) {
        self.vm = vm
    }

    private var connectionTask: Task<Void, Never>?
    private var connection: VZVirtioSocketConnection?
    private var channel: VirtualMessagingChannel?

    private var connectionAttempt = 0

    @MainActor
    func activate() {
        logger.debug(#function)

        connectionTask = Task.detached { [weak self] in
            guard let self else { return }

            if connectionAttempt == 0 {
                logger.debug("First connection attempt, waiting a bit...")

                try? await Task.sleep(for: .seconds(20))

                guard !Task.isCancelled else {
                    logger.warning("First connection attempt cancelled")
                    return
                }

                logger.debug("First connection attempt waiting period finished.")
            }

            connectionAttempt += 1

            await attemptConnection()
        }
    }

    @MainActor
    func invalidate() {
        try? channel?.invalidate()
        channel = nil

        connection?.close()
        connection = nil

        connectionTask?.cancel()
        connectionTask = nil
    }

    private func attemptConnection() async {
        guard !Task.isCancelled else {
            logger.debug("Connection task cancelled")
            return
        }

        logger.debug("Attempting connection...")

        do {
            try await connect()
        } catch {
            logger.warning("Guest connection: \(error, privacy: .public)")

            try? await Task.sleep(for: .seconds(1))

            await attemptConnection()
        }
    }

    private func connect() async throws {
        guard let vm else {
            throw Failure("VM not available.")
        }

        guard vm.state == .running else {
            throw Failure("VM not running.")
        }

        guard let socketDevice = vm.socketDevices.first as? VZVirtioSocketDevice else {
            throw Failure("Virtio socket device not available.")
        }

        logger.debug("Performing socket device connection...")

        let newConnection = try await createConnection(with: socketDevice)

        logger.debug("Socket connected")

        self.connection = newConnection

        let newChannel = VirtualMessagingChannel(type: .client, address: .fileDescriptor(newConnection.fileDescriptor))
        self.channel = newChannel

        let eventTask = Task {
            for await event in newChannel.events {
                switch event {
                case .connected:
                    logger.info("Channel connected")
                case .disconnected:
                    logger.info("Channel disconnected")
                    return
                }
            }
        }

        Task {
            for await message in newChannel.messages {
                logger.log("Received message: \(message, privacy: .public)")
            }
        }

        try await newChannel.activate()

        try await Task.sleep(for: .milliseconds(200))

        guard await newChannel.hasConnection else {
            throw "Connection failed."
        }

        logger.notice("Channel created")

        await eventTask.value

        throw "Disconnected"
    }

    private func createConnection(with socketDevice: VZVirtioSocketDevice, port: UInt32 = 1024) async throws -> VZVirtioSocketConnection {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                socketDevice.connect(toPort: port) { result in
                    continuation.resume(with: result)
                }
            }
        }
    }

}

public struct TestVMPayload: RoutableMessagePayload {
    public var id = UUID()
    public var timestamp = Date.now.timeIntervalSinceReferenceDate
    public init(id: UUID = UUID(), timestamp: TimeInterval = Date.now.timeIntervalSinceReferenceDate) {
        self.id = id
        self.timestamp = timestamp
    }
}
