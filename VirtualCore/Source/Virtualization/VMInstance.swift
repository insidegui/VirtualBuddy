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
import VMBridge
import VMBridgeVirtualization
import ManagedPreferencesKit

@MainActor
public final class VMInstance: NSObject, ObservableObject {

    private let library: VMLibraryController

    private let logger: Logger

    var options = VMSessionOptions.default

    private var _virtualMachine: VZVirtualMachine?
    private var runtimeConfiguration: VZVirtualMachineConfiguration?

    private var sharedFoldersPolicyObservation: ManagedPreferenceObservation?

    private var networkAttachmentHelper: VMNetworkAttachmentHelper?

    private var usbDeviceControllerStorage: AnyObject?

    @available(macOS 27.0, *)
    private(set) var usbDeviceController: VMUSBDeviceController? {
        get { usbDeviceControllerStorage as? VMUSBDeviceController }
        set { usbDeviceControllerStorage = newValue }
    }
    
    var virtualMachine: VZVirtualMachine {
        get throws {
            guard let vm = _virtualMachine else {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
            
            return vm
        }
    }
    
    private var guestSession: HostGuestSession?
    private var guestRunTask: Task<Void, Never>?
    private var didHandleStop = false

    deinit { guestRunTask?.cancel() }
    
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

        if model.guestAppSupport == .full {
            c.socketDevices = [VZVirtioSocketDeviceConfiguration()]
        }
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

        await stopGuestCommunication()
        let installImage: URL?
        if options.bootOnInstallDevice {
            installImage = virtualMachineModel.metadata.installImageURL
        } else {
            installImage = nil
        }
        let config = try await Self.makeConfiguration(for: virtualMachineModel, installImageURL: installImage, savedState: savedState) // add install iso here for linux (hack)

        do {
            try config.validate()

            logger.info("Configuration validated")
        } catch {
            logger.fault("Invalid configuration: \(String(describing: error))")
            
            throw Failure("Failed to validate configuration: \(String(describing: error))")
        }

        networkAttachmentHelper?.stop()

        let virtualMachine = VZVirtualMachine(configuration: config)
        didHandleStop = false
        _virtualMachine = virtualMachine
        runtimeConfiguration = config
        sharedFoldersPolicyObservation = VirtualBuddyManagedPreferences.schema.reader()
            .observeChanges(for: .disableSharedFolders) { [weak self] in
                self?.enforceSharedFoldersPolicy()
            }
        enforceSharedFoldersPolicy()
        networkAttachmentHelper = VMNetworkAttachmentHelper(
            virtualMachine: virtualMachine,
            configuration: config,
            logger: logger
        )
    }

    private func startGuestCommunication() throws {
        guard virtualMachineModel.guestAppSupport == .full else { return }
        let vm = try virtualMachine
        guard let device = vm.socketDevices.first as? VZVirtioSocketDevice else {
            throw Failure("The guest communication socket device is unavailable.")
        }
        let session = HostGuestSession(connection: .host(socketDevice: device, port: GuestCommunication.port))
        session.onNotification = { [weak self] name in
            self?.logger.debug("Guest system notification: \(name, privacy: .public)")
        }
        session.onDesktopPicture = { [weak self] picture in
            guard let self, let image = NSImage(data: picture.content) else { return }
            do {
                let url = self.virtualMachineModel.metadataFileURL(VBVirtualMachine.thumbnailFileName)
                try picture.content.write(to: url, options: .atomic)
                if let hash = image.blurHash(numberOfComponents: (Int.vbBlurHashSize, Int.vbBlurHashSize)) {
                    self.virtualMachineModel.metadata.backgroundHash = BlurHashToken(value: hash, size: .vbBlurHashSize)
                }
                try self.virtualMachineModel.saveMetadata()
            } catch {
                self.logger.error("Error saving guest desktop picture: \(error, privacy: .public)")
            }
        }
        guestSession = session
        guestRunTask = session.start()
    }

    func stopGuestCommunication() async {
        let session = guestSession
        guestSession = nil
        guestRunTask?.cancel()
        await session?.stop()
        guestRunTask = nil
    }

    func startVM() async throws {
        try await bootstrap()

        do {
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

            enforceSharedFoldersPolicy()
            networkAttachmentHelper?.enforcePolicy()
            try runtimeConfiguration.require("The VM configuration is unavailable.")
                .validateMicrophonePolicy(preferences: VirtualBuddyManagedPreferences.schema.reader())
            try await vm.start(options: startOptions)
            enforceSharedFoldersPolicy()

            networkAttachmentHelper?.startMonitoringHostInterfaces()
            startUSBDeviceMonitoring(for: vm)

            #if DEBUG
            VBDebugUtil.debugVirtualMachine(afterStart: vm)
            #endif
        } catch {
            await stopGuestCommunication()
            library.unregisterBootedVM(self)
            throw error
        }
    }

    private func bootstrap(savedState: VBSavedStatePackage? = nil) async throws {
        try await createVirtualMachine(savedState: savedState)

        let vm = try ensureVM()

        vm.delegate = self
        try startGuestCommunication()

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
        
        enforceSharedFoldersPolicy()
        networkAttachmentHelper?.enforcePolicy()
        if #available(macOS 27.0, *) { await usbDeviceController?.enforcePolicy() }
        try runtimeConfiguration.require("The VM configuration is unavailable.")
            .validateMicrophonePolicy(preferences: VirtualBuddyManagedPreferences.schema.reader())
        try await vm.resume()
        enforceSharedFoldersPolicy()
    }

    private func enforceSharedFoldersPolicy() {
        guard VirtualBuddyManagedPreferences.sharedFoldersDisabled, let vm = _virtualMachine else { return }

        for case let device as VZVirtioFileSystemDevice in vm.directorySharingDevices {
            guard device.tag == VBSharedFolder.virtualBuddyShareName, device.share != nil else { continue }
            device.share = nil
            logger.notice("Host folder sharing disconnected by DisableSharedFolders")
        }
    }
    
    func stop() async throws {
        logger.debug(#function)

        let vm = try ensureVM()
        
        try vm.requestStop()
    }
    
    func forceStop() async throws {
        logger.debug(#function)

        let vm = try ensureVM()
        
        await stopGuestCommunication()
        do {
            try await vm.stop()
        } catch {
            try? startGuestCommunication()
            throw error
        }

        networkAttachmentHelper?.stop()
        stopUSBDeviceMonitoring()

        library.unregisterBootedVM(self)
    }

    /// Replaces every supported network attachment on the running VM.
    ///
    /// Automatic bridge configurations remain pinned to the interface selected when the VM was
    /// created. This avoids unexpectedly moving the guest's MAC address to a different network.
    func reconnectNetwork() throws {
        guard let networkAttachmentHelper else {
            throw Failure("The virtual machine's network attachment manager is unavailable.")
        }

        try networkAttachmentHelper.reconnectAll()
    }

    var activeBridgeInterfaceIdentifiers: Set<String> {
        networkAttachmentHelper?.bridgeInterfaceIdentifiers ?? []
    }

    var hasBridgedNetworkAttachments: Bool {
        networkAttachmentHelper?.hasBridgedAttachments == true
    }

    func changeBridgeInterface(to interfaceIdentifier: String) throws {
        guard let networkAttachmentHelper else {
            throw Failure("The virtual machine's network attachment manager is unavailable.")
        }

        try networkAttachmentHelper.changeBridgeInterface(to: interfaceIdentifier)
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
            enforceSharedFoldersPolicy()
            try await vm.restoreMachineStateFrom(url: package.dataFileURL)

            logger.log("Successfully restored state from \(package.dataFileURL.path), resuming VM")

            try await resume()

            networkAttachmentHelper?.startMonitoringHostInterfaces()
            startUSBDeviceMonitoring(for: vm)

            #if DEBUG
            VBDebugUtil.debugVirtualMachine(afterStart: vm)
            #endif
        } catch {
            await stopGuestCommunication()
            library.unregisterBootedVM(self)
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

    private func startUSBDeviceMonitoring(for virtualMachine: VZVirtualMachine) {
        guard #available(macOS 27.0, *) else { return }

        usbDeviceController?.stop()

        let controller = VMUSBDeviceController(
            virtualMachine: virtualMachine,
            configuredDevices: virtualMachineModel.configuration.hardware.usbDevices,
            logger: logger
        )
        usbDeviceController = controller
        controller.start()
    }

    private func stopUSBDeviceMonitoring() {
        guard #available(macOS 27.0, *) else { return }

        usbDeviceController?.stop()
        usbDeviceController = nil
    }
    
}

// MARK: - VZVirtualMachineDelegate

extension VMInstance: VZVirtualMachineDelegate {
    
    public nonisolated func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        MainActor.assumeIsolated {
            guard virtualMachine === self._virtualMachine else { return }
            handleGuestStopped(with: error)
        }
    }

    public nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        MainActor.assumeIsolated {
            guard virtualMachine === self._virtualMachine else { return }
            handleGuestStopped(with: nil)
        }
    }
    
    public nonisolated func virtualMachine(_ virtualMachine: VZVirtualMachine, networkDevice: VZNetworkDevice, attachmentWasDisconnectedWithError error: Error) {
        MainActor.assumeIsolated {
            networkAttachmentHelper?.attachmentWasDisconnected(
                in: virtualMachine,
                networkDevice: networkDevice,
                error: error
            )
        }
    }

    private func handleGuestStopped(with error: Error?) {
        networkAttachmentHelper?.stop()
        stopUSBDeviceMonitoring()

        guard !didHandleStop else { return }
        didHandleStop = true

        if let error {
            logger.error("Guest stopped with error: \(String(describing: error), privacy: .public)")
        } else {
            logger.debug("Guest stopped")
        }

        Task { [self] in
            await stopGuestCommunication()
            library.unregisterBootedVM(self)
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
