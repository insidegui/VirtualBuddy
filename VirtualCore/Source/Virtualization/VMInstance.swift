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

    private struct NetworkAttachmentRecoveryConfiguration {
        enum Kind {
            case NAT
            case bridge(interfaceIdentifier: String)
        }

        let kind: Kind
        let macAddress: String

        var description: String {
            switch kind {
            case .NAT:
                return "NAT"
            case .bridge(let interfaceIdentifier):
                return "bridge(\(interfaceIdentifier))"
            }
        }

        func makeAttachment() throws -> VZNetworkDeviceAttachment {
            switch kind {
            case .NAT:
                return VZNATNetworkDeviceAttachment()
            case .bridge(let interfaceIdentifier):
                guard let interface = VZBridgedNetworkInterface.networkInterfaces.first(where: {
                    $0.identifier == interfaceIdentifier
                }) else {
                    throw Failure("The bridged network interface \(interfaceIdentifier.quoted) is not currently available.")
                }

                return VZBridgedNetworkDeviceAttachment(interface: interface)
            }
        }
    }

    private struct NetworkAttachmentRecoveryTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private static let networkAttachmentRecoveryDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    private static let networkAttachmentStabilizationDelay: TimeInterval = 1

    private let library: VMLibraryController

    private let logger: Logger

    var options = VMSessionOptions.default

    private var _virtualMachine: VZVirtualMachine?

    private var networkAttachmentRecoveryConfigurations: [NetworkAttachmentRecoveryConfiguration?] = []
    private var networkAttachmentRecoveryTasks: [Int: NetworkAttachmentRecoveryTask] = [:]
    
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
    private(set) var isRecoveryBoot = false

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

    public static func makeConfiguration(for model: VBVirtualMachine, installImageURL: URL? = nil, savedState: VBSavedStatePackage? = nil) async throws -> VZVirtualMachineConfiguration {
        let helper: VirtualMachineConfigurationHelper
        let platform: VZPlatformConfiguration
        let installDevice: [VZStorageDeviceConfiguration]
        switch model.configuration.systemType {
        case .mac:
            helper = MacOSVirtualMachineConfigurationHelper(vm: model, savedState: savedState)
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
        
        return c
    }
    
    private func createVirtualMachine(savedState: VBSavedStatePackage?) async throws {
        logger.debug(#function)

        let installImage: URL?
        if options.bootOnInstallDevice {
            installImage = virtualMachineModel.metadata.installImageURL
        } else {
            installImage = nil
        }
        let config = try await Self.makeConfiguration(for: virtualMachineModel, installImageURL: installImage, savedState: savedState) // add install iso here for linux (hack)

        await setupWormhole(for: config)

        do {
            try config.validate()

            logger.info("Configuration validated")
        } catch {
            logger.fault("Invalid configuration: \(String(describing: error))")
            
            throw Failure("Failed to validate configuration: \(String(describing: error))")
        }

        let virtualMachine = VZVirtualMachine(configuration: config)
        _virtualMachine = virtualMachine
        configureNetworkAttachmentRecovery(with: config)
    }

    private func configureNetworkAttachmentRecovery(with configuration: VZVirtualMachineConfiguration) {
        cancelNetworkAttachmentRecovery()

        networkAttachmentRecoveryConfigurations = configuration.networkDevices.enumerated().map { index, device in
            guard let attachment = device.attachment else {
                logger.error("Network device \(index) has no attachment; automatic recovery will be unavailable for this device")
                return nil
            }

            let recoveryKind: NetworkAttachmentRecoveryConfiguration.Kind

            switch attachment {
            case is VZNATNetworkDeviceAttachment:
                recoveryKind = .NAT
            case let bridge as VZBridgedNetworkDeviceAttachment:
                recoveryKind = .bridge(interfaceIdentifier: bridge.interface.identifier)
            default:
                logger.error("Network device \(index) uses unsupported attachment type \(String(describing: type(of: attachment)), privacy: .public); automatic recovery will be unavailable for this device")
                return nil
            }

            return NetworkAttachmentRecoveryConfiguration(
                kind: recoveryKind,
                macAddress: device.macAddress.string.uppercased()
            )
        }
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
        streamGuestDesktopPictureMessages()
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

    public func streamGuestDesktopPictureMessages() {
        logger.debug(#function)

        let task = Task {
            do {
                for await message in try await wormhole.desktopPictureMessages(from: virtualMachineModel.wormholeID) {
                    do {
                        let fileURL = virtualMachineModel.metadataFileURL(VBVirtualMachine.thumbnailFileName)

                        try message.content.write(to: fileURL, options: .atomic)

                        if let image = NSImage(data: message.content),
                           let blurHash = image.blurHash(numberOfComponents: (Int.vbBlurHashSize, Int.vbBlurHashSize))
                        {
                            virtualMachineModel.metadata.backgroundHash = BlurHashToken(value: blurHash, size: .vbBlurHashSize)
                        }

                        try virtualMachineModel.saveMetadata()
                    } catch {
                        logger.error("Error handling desktop picture message: \(error, privacy: .public)")
                    }
                }
            } catch {
                logger.error("Error subscribing to desktop picture messages: \(error, privacy: .public)")
            }
        }

        guestIOTasks.append(task)
    }

    func startVM() async throws {
        try await bootstrap()

        let vm = try ensureVM()

        let configuration = virtualMachineModel.configuration
        let startOptions: VZVirtualMachineStartOptions

        switch configuration.systemType {
        case .mac:
            let macOptions = VZMacOSVirtualMachineStartOptions(options: options)
            if #available(macOS 27.0, *),
               let provisioning = MacOSVirtualMachineConfigurationHelper.createProvisioningOptions(for: virtualMachineModel)
            {
                try macOptions.setGuestProvisioning(provisioning)
            }
            startOptions = macOptions
            isRecoveryBoot = macOptions.startUpFromMacOSRecovery
        case .linux:
            startOptions = VZVirtualMachineStartOptions()
        }

        try await vm.start(options: startOptions)

        #if DEBUG
        VBDebugUtil.debugVirtualMachine(afterStart: vm)
        #endif
    }

    private func bootstrap(savedState: VBSavedStatePackage? = nil) async throws {
        try await createVirtualMachine(savedState: savedState)

        let vm = try ensureVM()

        vm.delegate = self

        library.registerBootedVM(self)

        #if DEBUG
        VBDebugUtil.debugVirtualMachine(beforeStart: vm)
        #endif
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

        cancelNetworkAttachmentRecovery()

        library.unregisterBootedVM(self)
    }

    /// Replaces every supported network attachment on the running VM.
    ///
    /// Automatic bridge configurations remain pinned to the interface selected when the VM was
    /// created. This avoids unexpectedly moving the guest's MAC address to a different network.
    func reconnectNetwork() throws {
        let virtualMachine = try ensureVM()
        var scheduledDeviceCount = 0

        for index in virtualMachine.networkDevices.indices {
            guard networkAttachmentRecoveryConfigurations.indices.contains(index),
                  networkAttachmentRecoveryConfigurations[index] != nil
            else { continue }

            scheduleNetworkAttachmentRecovery(
                forDeviceAt: index,
                in: virtualMachine,
                replacingCurrentAttachment: true
            )
            scheduledDeviceCount += 1
        }

        guard scheduledDeviceCount > 0 else {
            throw Failure("This virtual machine has no network attachments that can be reconnected.")
        }

        logger.info("Manual network reconnection scheduled for \(scheduledDeviceCount) device(s)")
    }

    @available(macOS 14.0, *)
    @discardableResult
    func saveState(snapshotName name: String, onStart: () -> ()) async throws -> VBSavedStatePackage {
        logger.debug(#function)

        let vm = try ensureVM()

        guard confirmSaveStateIfNotOnAPFSVolume() else {
            logger.info("State save denied by user.")
            throw CancellationError()
        }

        /// Callback so that caller may update UI to indicate that saving has actually started,
        /// but only after the user has performed pre-save confirmation steps.
        onStart()

        logger.debug("Pausing to save state")

        try await pause()

        logger.debug("VM paused, requesting state save")

        let package = try virtualMachineModel.createSavedStatePackage(in: library, snapshotName: name)

        logger.debug("VM state package will be written to \(package.url.path)")

        do {
            try await package.createStorageDeviceClones(model: virtualMachineModel)

            try await vm.saveMachineStateTo(url: package.dataFileURL)

            logger.log("VM state saved to \(package.dataFileURL.path)")

            return package
        } catch {
            try? FileManager.default.removeItem(at: package.url)

            logger.error("VM state save failed: \(error, privacy: .public)")

            throw error
        }
    }

    /// Asks user for confirmation before saving state if the volume where the VirtualBuddy library
    /// resides is not an APFS volume, meaning that cloning is not available.
    @available(macOS 14.0, *)
    private func confirmSaveStateIfNotOnAPFSVolume() -> Bool {
        guard !library.isInAPFSVolume else { return true }

        let suppressionKey = "SuppressConfirmSaveStateNonAPFSVolumeAlert"
        guard !UserDefaults.standard.bool(forKey: suppressionKey) else { return true }

        let alert = NSAlert()
        alert.messageText = "Disk Space Warning"
        alert.informativeText = """
        It seems like your virtual machine data can’t be cloned because your library isn’t in an APFS volume.
        
        Creating this snapshot might take up several gigabytes of storage space.
        
        Would you like to continue?
        """
        alert.addButton(withTitle: "Create Snapshot")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressionKey)
        }

        return true
    }

    @available(macOS 14.0, *)
    func restoreState(from package: VBSavedStatePackage, updateHandler: (_ vm: VZVirtualMachine, _ package: VBSavedStatePackage) async -> Void) async throws {
        logger.debug("Restore state requested with package \(package.url.path)")

        try await runSavedStateMigrationIfNeeded(for: package)

        try package.validate(for: virtualMachineModel)

        if _virtualMachine == nil {
            logger.debug("Bootstrapping VM for state restoration")

            try await bootstrap(savedState: package)
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

    @available(macOS 14.0, *)
    private func runSavedStateMigrationIfNeeded(for package: VBSavedStatePackage) async throws {
        guard package.needsStorageCloneMigration else { return }

        guard confirmSavedStateMigration() else {
            throw CancellationError()
        }

        guard confirmSaveStateIfNotOnAPFSVolume() else {
            throw CancellationError()
        }

        try await package.createStorageDeviceClones(model: virtualMachineModel)
    }

    @available(macOS 14.0, *)
    private func confirmSavedStateMigration() -> Bool {
        let suppressionKey = "SuppressConfirmSavedStateMigrationAlert"

        guard !UserDefaults.standard.bool(forKey: suppressionKey) else { return true }

        let alert = NSAlert()
        alert.messageText = "Migration Required"
        alert.informativeText = """
        The virtual machine’s state was saved in an older version of VirtualBuddy that didn’t create clones of the storage devices. \
        This could lead to data corruption over time.

        To use this saved state, we need to migrate it to include storage device clones.
        """
        alert.addButton(withTitle: "Migrate and Restore")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressionKey)
        }

        return true
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
    
    public nonisolated func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        MainActor.assumeIsolated {
            handleGuestStopped(with: error)
        }
    }

    public nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        MainActor.assumeIsolated {
            handleGuestStopped(with: nil)
        }
    }
    
    public nonisolated func virtualMachine(_ virtualMachine: VZVirtualMachine, networkDevice: VZNetworkDevice, attachmentWasDisconnectedWithError error: Error) {
        MainActor.assumeIsolated {
            handleNetworkAttachmentDisconnection(
                in: virtualMachine,
                networkDevice: networkDevice,
                error: error
            )
        }
    }

    private func handleNetworkAttachmentDisconnection(
        in virtualMachine: VZVirtualMachine,
        networkDevice: VZNetworkDevice,
        error: Error
    ) {
        let nsError = error as NSError
        let attachmentDescription = String(describing: networkDevice.attachment)

        guard let deviceIndex = virtualMachine.networkDevices.firstIndex(where: { $0 === networkDevice }) else {
            logger.error("A network attachment disconnected but its device is not part of the VM: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) error=\(nsError.localizedDescription, privacy: .public) userInfo=\(String(describing: nsError.userInfo), privacy: .public) attachment=\(attachmentDescription, privacy: .public)")
            return
        }

        let macAddress = networkAttachmentRecoveryConfigurations.indices.contains(deviceIndex)
            ? networkAttachmentRecoveryConfigurations[deviceIndex]?.macAddress ?? "unknown"
            : "unknown"

        logger.error("Network attachment disconnected: device=\(deviceIndex) MAC=\(macAddress, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) error=\(nsError.localizedDescription, privacy: .public) userInfo=\(String(describing: nsError.userInfo), privacy: .public) attachment=\(attachmentDescription, privacy: .public)")

        guard _virtualMachine === virtualMachine else {
            logger.info("Ignoring network disconnection from a stale VM instance")
            return
        }

        guard networkAttachmentRecoveryConfigurations.indices.contains(deviceIndex),
              networkAttachmentRecoveryConfigurations[deviceIndex] != nil
        else {
            logger.error("No recovery configuration is available for network device \(deviceIndex)")
            return
        }

        guard networkAttachmentRecoveryTasks[deviceIndex] == nil else {
            logger.debug("Network recovery is already active for device \(deviceIndex)")
            return
        }

        scheduleNetworkAttachmentRecovery(forDeviceAt: deviceIndex, in: virtualMachine)
    }

    private func scheduleNetworkAttachmentRecovery(
        forDeviceAt deviceIndex: Int,
        in virtualMachine: VZVirtualMachine,
        replacingCurrentAttachment: Bool = false
    ) {
        guard virtualMachine.networkDevices.indices.contains(deviceIndex),
              networkAttachmentRecoveryConfigurations.indices.contains(deviceIndex),
              let recoveryConfiguration = networkAttachmentRecoveryConfigurations[deviceIndex]
        else {
            logger.error("Unable to schedule recovery for network device \(deviceIndex): recovery configuration is unavailable")
            return
        }

        if let existingTask = networkAttachmentRecoveryTasks.removeValue(forKey: deviceIndex) {
            existingTask.task.cancel()
        }

        let networkDevice = virtualMachine.networkDevices[deviceIndex]
        let taskID = UUID()
        let initialDelay: TimeInterval = replacingCurrentAttachment ? 0 : Self.networkAttachmentRecoveryDelays[0]

        let task = Task { @MainActor [weak self, weak virtualMachine, weak networkDevice] in
            var attempt = 0
            var shouldReplaceCurrentAttachment = replacingCurrentAttachment
            var nextDelay = initialDelay

            defer {
                self?.networkAttachmentRecoveryDidFinish(forDeviceAt: deviceIndex, taskID: taskID)
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(nextDelay))
                } catch {
                    return
                }

                guard let self, let virtualMachine, let networkDevice,
                      self._virtualMachine === virtualMachine
                else { return }

                if networkDevice.attachment != nil && !shouldReplaceCurrentAttachment {
                    self.logger.info("Network device \(deviceIndex) recovered before retry was necessary")
                    return
                }

                shouldReplaceCurrentAttachment = false
                attempt += 1

                self.logger.info("Attempting to reconnect network device \(deviceIndex) (\(recoveryConfiguration.description, privacy: .public), MAC=\(recoveryConfiguration.macAddress, privacy: .public), attempt=\(attempt))")

                do {
                    let newAttachment = try recoveryConfiguration.makeAttachment()
                    networkDevice.attachment = newAttachment

                    self.logger.debug("Assigned new attachment to network device \(deviceIndex): \(String(describing: newAttachment), privacy: .public)")

                    try await Task.sleep(for: .seconds(Self.networkAttachmentStabilizationDelay))

                    guard self._virtualMachine === virtualMachine else { return }

                    if networkDevice.attachment != nil {
                        self.logger.info("Successfully reconnected network device \(deviceIndex) (\(recoveryConfiguration.description, privacy: .public), MAC=\(recoveryConfiguration.macAddress, privacy: .public))")
                        return
                    }

                    self.logger.error("Network device \(deviceIndex) rejected the replacement attachment; retrying")
                } catch is CancellationError {
                    return
                } catch {
                    self.logger.error("Failed to reconnect network device \(deviceIndex) on attempt \(attempt): \(error, privacy: .public)")
                }

                let delayIndex = min(attempt, Self.networkAttachmentRecoveryDelays.count - 1)
                nextDelay = Self.networkAttachmentRecoveryDelays[delayIndex]
            }
        }

        networkAttachmentRecoveryTasks[deviceIndex] = NetworkAttachmentRecoveryTask(id: taskID, task: task)
    }

    private func networkAttachmentRecoveryDidFinish(forDeviceAt deviceIndex: Int, taskID: UUID) {
        guard networkAttachmentRecoveryTasks[deviceIndex]?.id == taskID else { return }

        networkAttachmentRecoveryTasks.removeValue(forKey: deviceIndex)
    }

    private func cancelNetworkAttachmentRecovery() {
        networkAttachmentRecoveryTasks.values.forEach { $0.task.cancel() }
        networkAttachmentRecoveryTasks.removeAll()
    }

    private func handleGuestStopped(with error: Error?) {
        cancelNetworkAttachmentRecovery()

        guestIOTasks.forEach { $0.cancel() }
        guestIOTasks.removeAll()

        if let error {
            logger.error("Guest stopped with error: \(String(describing: error), privacy: .public)")
        } else {
            logger.debug("Guest stopped")
        }

        DispatchQueue.main.async { [self] in
            library.unregisterBootedVM(self)

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
