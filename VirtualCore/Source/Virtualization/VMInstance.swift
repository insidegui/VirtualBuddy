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

    /// The model that was used to construct the virtual machine. When restoring a saved session, its configuration
    /// is the one that was captured when the session was saved rather than the current one.
    private var runtimeModel: VBVirtualMachine

    /// The guest additions image that's attached to the running virtual machine.
    private(set) var guestAdditionsMediaURL: URL?

    /// The model the virtual machine is running with.
    var effectiveModel: VBVirtualMachine { runtimeModel }

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

    /// Whether the guest app running in the virtual machine is currently connected to the host.
    @Published private(set) var isGuestAppConnected = false
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
        self.runtimeModel = vm
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
        try await createMacPlatform(for: model, installImageURL: installImageURL, requiresExistingIdentity: false)
    }

    /// - Parameter requiresExistingIdentity: When `true`, the hardware model, machine identifier and auxiliary storage
    /// must already exist. Their absence is an error because generating them would give the guest a different identity.
    static func createMacPlatform(for model: VBVirtualMachine, installImageURL: URL?, requiresExistingIdentity: Bool) async throws -> VZMacPlatformConfiguration {
        if requiresExistingIdentity {
            for url in [model.hardwareModelURL, model.machineIdentifierURL, model.auxiliaryStorageURL] where !FileManager.default.fileExists(atPath: url.path) {
                throw SavedSessionError.missingResource(url.lastPathComponent)
            }
        }

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
        try await makeRuntimeConfiguration(for: model, installImageURL: installImageURL, restoration: nil).configuration
    }

    struct RuntimeConfiguration {
        let configuration: VZVirtualMachineConfiguration
        let guestAdditionsMediaURL: URL?
    }

    static func makeRuntimeConfiguration(for model: VBVirtualMachine, installImageURL: URL?, restoration: SavedSessionRestoration?) async throws -> RuntimeConfiguration {
        let helper: VirtualMachineConfigurationHelper
        let platform: VZPlatformConfiguration
        let installDevice: [VZStorageDeviceConfiguration]
        switch model.configuration.systemType {
        case .mac:
            helper = MacOSVirtualMachineConfigurationHelper(vm: model, restoration: restoration)
            platform = try await Self.createMacPlatform(for: model, installImageURL: installImageURL, requiresExistingIdentity: restoration != nil)
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

        if model.configuration.guestAdditionsEnabled, model.guestAppSupport == .full {
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

        return RuntimeConfiguration(configuration: c, guestAdditionsMediaURL: await helper.guestAdditionsMediaURL())
    }

    private func createVirtualMachine(restoration: SavedSessionRestoration?) async throws {
        logger.debug(#function)

        await stopGuestCommunication()
        let installImage: URL?
        if options.bootOnInstallDevice, restoration == nil {
            installImage = virtualMachineModel.metadata.installImageURL
        } else {
            installImage = nil
        }

        /// A restored virtual machine is constructed from the configuration that was captured when the session was saved,
        /// so that later changes to the settings can't make it differ from the saved memory.
        var model = virtualMachineModel
        if let restoration {
            model.configuration = restoration.configuration
        }

        let runtime = try await Self.makeRuntimeConfiguration(for: model, installImageURL: installImage, restoration: restoration)
        let config = runtime.configuration

        do {
            try config.validate()

            logger.info("Configuration validated")
        } catch {
            logger.fault("Invalid configuration: \(String(describing: error))")
            
            throw Failure("Failed to validate configuration: \(String(describing: error))")
        }

        runtimeModel = model
        guestAdditionsMediaURL = runtime.guestAdditionsMediaURL

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
        guard runtimeModel.configuration.guestAdditionsEnabled,
              runtimeModel.guestAppSupport == .full else { return }
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
        observeGuestConnection(in: session)
    }

    private func observeGuestConnection(in session: HostGuestSession) {
        isGuestAppConnected = withObservationTracking {
            session.isConnected
        } onChange: { [weak self, weak session] in
            Task { @MainActor in
                guard let self, let session, self.guestSession === session else { return }
                self.observeGuestConnection(in: session)
            }
        }
    }

    func stopGuestCommunication() async {
        let session = guestSession
        guestSession = nil
        isGuestAppConnected = false
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

    private func bootstrap(restoration: SavedSessionRestoration? = nil) async throws {
        try await createVirtualMachine(restoration: restoration)

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
        removeWorkingGuestAdditionsMedia()

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

    // MARK: Saved Sessions

    /// Eligibility determined from the configuration the virtual machine is actually running with.
    var runtimeSaveEligibility: SavedSessionEligibility {
        guard let runtimeConfiguration else { return .supported }

        var eligibility = SavedSessionEligibility.evaluate(runtimeConfiguration: runtimeConfiguration)

        if #available(macOS 27.0, *), usbDeviceController?.devices.contains(where: \.isAttached) == true {
            eligibility.issues.append(.usbDeviceAttached)
        }

        return eligibility
    }

    /// Pauses the virtual machine if it's running.
    /// - Returns: `true` if the virtual machine was running, `false` if it was already paused.
    func pauseForSaving() async throws -> Bool {
        let vm = try ensureVM()

        switch vm.state {
        case .running:
            try await pause()
            return true
        case .paused:
            return false
        default:
            throw Failure("The virtual machine can't be saved in its current state.")
        }
    }

    /// Describes everything that has to be captured for the virtual machine's session. Must be called while the virtual machine is paused.
    func makeSavedSessionCapturePlan(wasPausedBeforeSave: Bool) throws -> SavedSessionCapturePlan {
        let model = runtimeModel
        let runtimeConfiguration = try runtimeConfiguration.require("The VM configuration is unavailable.")

        var resources = [SavedSessionCapturePlan.ResourceSource]()

        for device in model.configuration.hardware.storageDevices where device.isEnabled {
            guard case .managedImage(let image) = device.backing else {
                throw SavedSessionError.notEligible(.externalDiskImage(device.displayName))
            }

            let url = model.diskImageURL(for: image)

            resources.append(.init(id: device.id, role: .disk, sourceURL: url, workingPath: url.lastPathComponent))
        }

        resources.append(.init(id: "auxiliaryStorage", role: .auxiliaryStorage, sourceURL: model.auxiliaryStorageURL, workingPath: model.auxiliaryStorageURL.lastPathComponent))
        resources.append(.init(id: "machineIdentifier", role: .machineIdentifier, sourceURL: model.machineIdentifierURL, workingPath: model.machineIdentifierURL.lastPathComponent))
        resources.append(.init(id: "hardwareModel", role: .hardwareModel, sourceURL: model.hardwareModelURL, workingPath: model.hardwareModelURL.lastPathComponent))

        if let guestAdditionsMediaURL {
            resources.append(.init(id: "guestAdditionsMedia", role: .guestAdditionsMedia, sourceURL: guestAdditionsMediaURL, workingPath: SavedSessionLayout.guestAdditionsMediaWorkingPath))
        }

        let screenshotURL = [VBVirtualMachine.screenshotFileName, VBVirtualMachine.thumbnailFileName]
            .map { virtualMachineModel.metadataFileURL($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }

        return SavedSessionCapturePlan(
            resources: resources,
            configuration: model.configuration,
            runtimeDescription: SavedSessionRuntimeDescription(configuration: runtimeConfiguration),
            screenshotSourceURL: screenshotURL,
            wasPausedBeforeSave: wasPausedBeforeSave,
            memorySize: runtimeConfiguration.memorySize
        )
    }

    func saveMachineState(to url: URL) async throws {
        let vm = try ensureVM()

        logger.debug("Saving machine state to \(url.path)")

        try await vm.saveMachineStateTo(url: url)
    }

    /// Stops the virtual machine and releases it after its session has been saved. Only the framework's stop is
    /// used because the saved session already holds everything that matters.
    func tearDownAfterSave() async throws {
        let vm = try ensureVM()

        try await vm.stop()

        await releaseStoppedVirtualMachine()
    }

    /// Releases a virtual machine that's not running anymore.
    func releaseStoppedVirtualMachine() async {
        didHandleStop = true
        networkAttachmentHelper?.stop()
        stopUSBDeviceMonitoring()
        await stopGuestCommunication()
        library.unregisterBootedVM(self)
        sharedFoldersPolicyObservation = nil
        _virtualMachine = nil
        runtimeConfiguration = nil
        removeWorkingGuestAdditionsMedia()
    }

    /// Constructs the virtual machine from a saved session and restores its memory and device state, leaving it paused.
    ///
    /// Nothing is generated or replaced during restoration: the identity and storage have been installed by the saved session
    /// transaction and the configuration is the one that was captured when the session was saved.
    func restoreSession(_ preparation: SavedSessionRestorePreparation, onConstructed: (VZVirtualMachine) -> Void) async throws {
        if preparation.guestAdditionsMediaURL != nil, VirtualBuddyManagedPreferences.guestAppDisabled {
            throw SavedSessionError.policyBlocksResume("The guest app disk image was attached when this session was saved, but it's now disabled by your organization. Discard the saved session to start this virtual machine.")
        }

        let restoration = SavedSessionRestoration(
            configuration: preparation.configuration,
            guestAdditionsMediaURL: preparation.guestAdditionsMediaURL
        )

        try await bootstrap(restoration: restoration)

        do {
            let vm = try ensureVM()
            let configuration = try runtimeConfiguration.require("The VM configuration is unavailable.")

            if let difference = SavedSessionRuntimeDescription(configuration: configuration).firstDifference(from: preparation.manifest.runtimeDescription) {
                throw SavedSessionError.configurationChanged(difference)
            }

            try configuration.validateSaveRestoreSupport()

            /// Policies that can't be applied to a session that's already running have to be found out now, while the saved session is still intact.
            do {
                try configuration.validateMicrophonePolicy(preferences: VirtualBuddyManagedPreferences.schema.reader())
            } catch {
                throw SavedSessionError.policyBlocksResume("Microphone input is disabled by your organization, but it was enabled when this session was saved and can't be turned off without restarting. Discard the saved session to start this virtual machine without microphone input.")
            }

            onConstructed(vm)

            enforceSharedFoldersPolicy()

            logger.debug("Restoring state from \(preparation.stateFileURL.path)")

            try await vm.restoreMachineStateFrom(url: preparation.stateFileURL)

            logger.log("Restored machine state, virtual machine is paused")
        } catch {
            await releaseStoppedVirtualMachine()

            logger.error("VM state restoration failed: \(error, privacy: .public)")

            throw error
        }
    }

    /// Resumes a virtual machine whose state was restored, then reconnects everything that depends on the guest running.
    func resumeRestoredSession() async throws {
        let vm = try ensureVM()

        try await resume()

        await stopGuestCommunication()
        try startGuestCommunication()

        networkAttachmentHelper?.startMonitoringHostInterfaces()
        startUSBDeviceMonitoring(for: vm)

        #if DEBUG
        VBDebugUtil.debugVirtualMachine(afterStart: vm)
        #endif
    }

    /// Reconnects the services that were stopped when the virtual machine was torn down for saving
    /// but wasn't actually released.
    func restartGuestCommunication() async {
        await stopGuestCommunication()
        do {
            try startGuestCommunication()
        } catch {
            logger.error("Failed to restart guest communication: \(error, privacy: .public)")
        }
    }

    func removeWorkingGuestAdditionsMedia() {
        try? SavedSessionStorage(bundleURL: virtualMachineModel.bundleURL).removeWorkingMedia()
        guestAdditionsMediaURL = nil
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
            configuredDevices: runtimeModel.configuration.hardware.usbDevices,
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
            removeWorkingGuestAdditionsMedia()
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
