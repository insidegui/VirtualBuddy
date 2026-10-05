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
    @DecodableDefault.False
    public var bootInRecoveryMode = false {
        didSet {
            guard bootInRecoveryMode != oldValue else { return }
            resolveMutuallyExclusiveOptions()
        }
    }

    @DecodableDefault.False
    public var bootInDFUMode = false {
        didSet {
            guard bootInDFUMode != oldValue else { return }
            resolveMutuallyExclusiveOptions()
        }
    }

    @DecodableDefault.False
    public var bootOnInstallDevice = false

    @DecodableDefault.False
    public var autoBoot = false

    public static let `default` = VMSessionOptions()

    public init(bootInRecoveryMode: Bool = false, bootInDFUMode: Bool = false, bootOnInstallDevice: Bool = false, autoBoot: Bool = false) {
        self.bootInRecoveryMode = bootInRecoveryMode
        self.bootInDFUMode = bootInDFUMode
        self.bootOnInstallDevice = bootOnInstallDevice
        self.autoBoot = autoBoot

        resolveMutuallyExclusiveOptions()
    }

    /// Whether these options boot the virtual machine in a way that can't continue a saved session.
    public var requestsSpecialBoot: Bool {
        bootInRecoveryMode || bootInDFUMode || bootOnInstallDevice
    }

    private mutating func resolveMutuallyExclusiveOptions() {
        if bootInDFUMode {
            bootInRecoveryMode = false
        }
        if bootInRecoveryMode {
            bootInDFUMode = false
        }
    }
}

/// The step a save or restore operation is currently performing.
public enum SavedSessionPhase: Equatable {
    case preparing
    case pausing
    case cloningStorage
    case savingMemory
    case finalizing
    case stopping

    case validating
    case installingStorage
    case restoringMemory
    case resuming

    /// How far along the operation is, based on which of its steps is running.
    public var fractionCompleted: Double {
        switch self {
        case .preparing: 0.0 / 6
        case .pausing: 1.0 / 6
        case .cloningStorage: 2.0 / 6
        case .savingMemory: 3.0 / 6
        case .finalizing: 4.0 / 6
        case .stopping: 5.0 / 6
        case .validating: 0.0 / 4
        case .installingStorage: 1.0 / 4
        case .restoringMemory: 2.0 / 4
        case .resuming: 3.0 / 4
        }
    }

    public var title: String {
        switch self {
        case .preparing: "Preparing"
        case .pausing: "Pausing"
        case .cloningStorage: "Cloning disks"
        case .savingMemory: "Saving memory"
        case .finalizing: "Finishing"
        case .stopping: "Stopping"
        case .validating: "Checking saved session"
        case .installingStorage: "Restoring disks"
        case .restoringMemory: "Restoring memory"
        case .resuming: "Resuming"
        }
    }
}

public enum VMState: Equatable {
    case idle
    case starting(_ message: String?)
    case resizingDisk(_ message: String?)
    case running(VZVirtualMachine)
    case paused(VZVirtualMachine)
    /// The virtual machine's session is being saved. It's paused while this happens.
    case saving(VZVirtualMachine, SavedSessionPhase)
    /// A saved session is being restored. The virtual machine is constructed during this operation.
    case restoring(VZVirtualMachine?, SavedSessionPhase)
    /// Not running, with a session saved and ready to be resumed.
    case saved(VBSavedSessionDescriptor)
    /// A saved session exists, but it can't be resumed without a decision from the user.
    case recoveryRequired(SavedSessionIssue)
    case stopped(Error?)
}

public enum MACAddressConflictResolution {
    case cancel
    case continueAnyway
    case randomize
}

@MainActor
public final class VMController: ObservableObject {

    public let id: VBVirtualMachine.ID
    private let name: String

    private let library: VMLibraryController

    private lazy var logger = Logger(for: Self.self)
    
    @Published
    public var options = VMSessionOptions.default {
        didSet {
            instance?.options = options
        }
    }
    
    public typealias State = VMState

    @Published
    public private(set) var state = State.idle

    /// Called from ``start()`` when the VM's MAC address collides with a currently-running VM.
    public var macAddressConflictHandler: (@MainActor ([MACAddressConflict]) async -> MACAddressConflictResolution)?
    
    private(set) var virtualMachine: VZVirtualMachine?

    @Published
    public var virtualMachineModel: VBVirtualMachine

    private var cancellables = Set<AnyCancellable>()

    private let guestAppDiskImage: GuestAdditionsDiskImage

    /// Serializes everything that changes the virtual machine's lifecycle.
    private let lease = VMOperationLease()

    /// Repeated requests to save join the one that's already running.
    private var inFlightSave: Task<Void, Error>?

    /// `true` between resuming a restored session and cleaning up the package it was restored from.
    private var isRestoreCompletionPending = false

    public init(with vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions? = nil) {
        self.id = vm.id
        self.name = vm.name
        self.virtualMachineModel = vm
        self.library = library
        self.guestAppDiskImage = GuestAdditionsDiskImage(source: vm.configuration.guestAppDiskImageSource)

        virtualMachineModel.reloadMetadata()
        if virtualMachineModel.metadata.installImageURL != nil && !virtualMachineModel.metadata.installFinished {
            self.options.bootOnInstallDevice = true
        }

        if let options {
            self.options = options
        }

        self.state = restingState

        /// Ensure configuration is persisted whenever it changes.
        $virtualMachineModel
            .dropFirst()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { updatedModel in
                do {
                    try updatedModel.saveMetadata()
                } catch {
                    assertionFailure("Failed to save configuration: \(error)")
                }
            }
            .store(in: &cancellables)

        library.addController(self)

        /// Make sure DFU mode flag is turned off if the app build doesn't allow DFU boot.
        if !VBMacConfiguration.appBuildAllowsDFUMode {
            self.options.bootInDFUMode = false
        }
    }

    private var instance: VMInstance?
    
    private func createInstance() throws -> VMInstance {
        let newInstance = VMInstance(with: virtualMachineModel, library: library, onVMStop: { [weak self] error in
            self?.handleInstanceStopped(error)
        })
        
        newInstance.options = options
        
        return newInstance
    }

    // MARK: Saved Session State

    /// The saved session that belongs to this virtual machine, if any.
    public var savedSession: VBSavedSessionDescriptor? { virtualMachineModel.savedSession }

    /// Whether this virtual machine's session can be saved, with the reason if it can't.
    ///
    /// Everything that can be determined without constructing the virtual machine is checked before it's started.
    /// While it's running, the configuration it's actually running with is checked too.
    public var saveEligibility: SavedSessionEligibility {
        let staticEligibility = SavedSessionEligibility.evaluate(
            model: instance?.effectiveModel ?? virtualMachineModel,
            options: options,
            supportsCloning: bundleSupportsCloning
        )

        guard let instance, state.isRunning || state.isPaused else { return staticEligibility }

        return staticEligibility.merging(instance.runtimeSaveEligibility)
    }

    /// Whether the volume where the virtual machine lives supports cloning, which saving a session depends on.
    /// Asked once because this is consulted every time a view that depends on it is updated.
    private lazy var bundleSupportsCloning = virtualMachineModel.bundleURL.volumeSupportsFileCloning

    /// The state the controller is in when nothing is running.
    private var restingState: State {
        guard let savedSession else { return .idle }

        switch savedSession.status {
        case .ready: return .saved(savedSession)
        case .recoveryRequired(let issue): return .recoveryRequired(issue)
        }
    }

    /// Re-reads the saved session from the virtual machine's bundle.
    public func reloadSavedSession() {
        virtualMachineModel.reloadSavedSession()

        guard state.isSavedSessionPresentation || state.isIdle else { return }

        state = restingState
    }

    private var storage: SavedSessionStorage { SavedSessionStorage(bundleURL: virtualMachineModel.bundleURL) }

    /// Sets the state to match what's actually happening to the virtual machine instead of assuming that a failure stopped it.
    private func reconcileState(after error: Error? = nil) {
        if let vm = try? instance?.virtualMachine {
            switch vm.state {
            case .running:
                state = .running(vm)
                return
            case .paused:
                state = .paused(vm)
                return
            default:
                break
            }
        }

        virtualMachineModel.reloadSavedSession()

        if savedSession != nil {
            state = restingState
        } else {
            state = .stopped(error)
        }
    }

    private func handleInstanceStopped(_ error: Error?) {
        /// Stop notifications that arrive when nothing is running (for example, from an instance that was already released) are not news.
        guard state.isRunning || state.isPaused || state.isStarting || state.isRestoring else { return }

        state = .stopped(error)

        Task { await finishRestoreIfPending() }
    }

    // MARK: Starting

    /// Starts the virtual machine, resuming its saved session if it has one, or booting it otherwise.
    ///
    /// - Parameter discardingSavedSession: Must only be `true` after the user has confirmed that the saved session will be lost.
    ///
    /// Starting in a way that can't continue a saved session (recovery, DFU, or the install device) throws
    /// ``SavedSessionError/discardConfirmationRequired`` unless the saved session is being discarded.
    public func start(discardingSavedSession: Bool = false) async throws {
        await lease.acquire()
        defer { lease.release() }

        /// Requests that arrive while another one is starting the virtual machine have nothing left to do.
        guard state.canStart else { return }

        /// A virtual machine that was saved but couldn't be stopped is still around. Only the recovery options can resolve that.
        if case .recoveryRequired(let issue) = state, issue.isStopFailure {
            throw SavedSessionError.recoveryRequired(issue)
        }

        if let session = lookUpSavedSession(), !discardingSavedSession {
            guard !options.requestsSpecialBoot else { throw SavedSessionError.discardConfirmationRequired }

            if let issue = session.issue {
                state = .recoveryRequired(issue)
                throw SavedSessionError.recoveryRequired(issue)
            }

            try await resumeSavedSession()
        } else {
            if discardingSavedSession {
                try await discardSavedSessionLocked()
            }

            try await bootVirtualMachine()
        }
    }

    /// Cleans up after interrupted operations and returns the current saved session.
    private func lookUpSavedSession() -> VBSavedSessionDescriptor? {
        _ = try? storage.recover()

        virtualMachineModel.reloadSavedSession()

        return savedSession
    }

    private func bootVirtualMachine() async throws {
        // Check for MAC address collisions with running VMs before changing state.
        guard await resolveMACAddressConflictsIfNeeded() else { return }

        state = .starting(nil)

        await waitForGuestDiskImageReadyIfNeeded()

        if virtualMachineModel.hasPendingDiskImageResizes {
            state = .resizingDisk("Checking disk images...")
            do {
                var updatedModel = virtualMachineModel
                let didResize = try await updatedModel.checkAndResizeDiskImages { message in
                    self.state = .resizingDisk(message)
                }
                virtualMachineModel = updatedModel
                if didResize {
                    presentDiskResizeCompletedAlert()
                }
            } catch {
                logger.warning("Failed to resize disk images: \(error, privacy: .public)")
                presentDiskResizeError(error)
                state = .stopped(error)
                throw error
            }
        }
        state = .starting("Starting virtual machine...")

        do {
            let newInstance = try createInstance()
            self.instance = newInstance

            try await newInstance.startVM()

            let vm = try newInstance.virtualMachine

            state = .running(vm)

            /// Update boot date VM metadata with the current date, only if not booting in recovery mode.
            if !newInstance.isRecoveryBoot {
                if virtualMachineModel.metadata.firstBootDate == nil {
                    logger.debug("Setting first boot date")
                    virtualMachineModel.metadata.firstBootDate = .now
                }
                virtualMachineModel.metadata.lastBootDate = .now
            }

            virtualMachineModel.metadata.installFinished = true
        } catch {
            reconcileState(after: error)
            throw error
        }
    }

    // MARK: Resuming a Saved Session

    /// Restores the saved session and resumes the virtual machine.
    ///
    /// The saved memory and the disks always belong together: the disks are replaced with clones from the saved session
    /// before the virtual machine is constructed, and the session is marked as consumed before execution can begin.
    /// If anything fails before that point, the saved session is left as it was.
    private func resumeSavedSession() async throws {
        let storage = self.storage

        state = .restoring(nil, .validating)

        let preparation: SavedSessionRestorePreparation

        do {
            let captured = try await performOffMainActor { try storage.capturedConfiguration() }

            let conflicts = library.activeCopyConflicts(
                for: virtualMachineModel,
                macAddresses: captured.hardware.networkDevices.map(\.macAddress)
            )
            guard conflicts.isEmpty else { throw SavedSessionError.activeCopyConflict(conflicts) }

            state = .restoring(nil, .installingStorage)

            preparation = try await performOffMainActor { try storage.prepareRestore() }
        } catch {
            reconcileState()
            throw wrapRestoreError(error)
        }

        let newInstance: VMInstance

        do {
            newInstance = try createInstance()
            instance = newInstance

            try await newInstance.restoreSession(preparation) { [self] vm in
                state = .restoring(vm, .restoringMemory)
            }
        } catch {
            /// Nothing has executed, so putting the files back keeps the saved session exactly as it was.
            instance = nil
            try? await performOffMainActor { try storage.cancelRestore() }
            reconcileState()
            throw wrapRestoreError(error)
        }

        let vm = try newInstance.virtualMachine

        state = .restoring(vm, .resuming)

        do {
            /// This has to be durable before resuming. The guest can start writing to the disks before the framework tells us it resumed.
            try await performOffMainActor { try storage.markConsumed(preparation) }
        } catch {
            await newInstance.releaseStoppedVirtualMachine()
            instance = nil
            try? await performOffMainActor { try storage.cancelRestore() }
            reconcileState()
            throw wrapRestoreError(error)
        }

        isRestoreCompletionPending = true

        do {
            try await newInstance.resumeRestoredSession()
        } catch {
            /// The virtual machine holds the restored state, paused. Resuming can be tried again,
            /// and the saved session stays consumed either way.
            state = .paused(vm)
            throw wrapRestoreError(error)
        }

        state = .running(vm)

        virtualMachineModel.metadata.lastBootDate = .now

        await finishRestoreIfPending()

        unhideCursor()
    }

    private func wrapRestoreError(_ error: Error) -> Error {
        switch error {
        case is CancellationError, SavedSessionError.activeCopyConflict, SavedSessionError.recoveryRequired, SavedSessionError.restoreFailed:
            error
        default:
            SavedSessionError.restoreFailed(error)
        }
    }

    /// Removes the package a session was restored from, once the virtual machine is running on its own.
    private func finishRestoreIfPending() async {
        guard isRestoreCompletionPending else { return }
        isRestoreCompletionPending = false

        let storage = self.storage

        do {
            try await performOffMainActor { try storage.completeRestore() }
        } catch {
            /// The consumed marker keeps the package from being restored again, so this is only housekeeping.
            logger.warning("Failed to clean up restored session: \(error, privacy: .public)")
        }

        virtualMachineModel.reloadSavedSession()
        library.reload(animated: false)
    }

    private func presentDiskResizeCompletedAlert() {
        let alert = NSAlert()
        alert.messageText = "Disk Image Expanded"
        alert.informativeText = "The disk image now has more space, but the guest operating system still needs to claim it. In a macOS guest, run 'diskutil apfs resizeContainer disk0s2 0' in Terminal after starting up. In other guests, use the system's partitioning tools."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentDiskResizeError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Disk Resize Failed"
        alert.informativeText = "VirtualBuddy couldn't resize disk images before startup. The virtual machine was not started.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Checks whether this virtual machine's network devices share a MAC address with any running virtual machine,
    /// asking the conflict handler how to proceed if so.
    ///
    /// - Returns: `true` if startup should continue, or `false` if the user chose to cancel the launch.
    private func resolveMACAddressConflictsIfNeeded() async -> Bool {
        guard let handler = macAddressConflictHandler else { return true }

        let conflicts = library.macAddressConflicts(for: virtualMachineModel)
        guard !conflicts.isEmpty else { return true }

        switch await handler(conflicts) {
        case .cancel:
            return false
        case .continueAnyway:
            return true
        case .randomize:
            for index in virtualMachineModel.configuration.hardware.networkDevices.indices {
                virtualMachineModel.configuration.hardware.networkDevices[index].macAddress = VZMACAddress.randomLocallyAdministered().string.uppercased()
            }
            return true
        }
    }

    /// If the virtual machine supports the guest app and has the toggle to auto-mount the guest image enabled,
    /// this method waits until the guest disk image is ready before returning.
    ///
    /// This is used to wait for the guest disk image to be ready before starting a virtual machine, which may occur
    /// if the user launches VirtualBuddy then quickly attempts to start up a machine right after installing an app update.
    ///
    /// It will also alert the user in case guest disk image generation has failed so that they know there's something wrong/
    private func waitForGuestDiskImageReadyIfNeeded() async {
        guard !VirtualBuddyManagedPreferences.guestAppDisabled,
           virtualMachineModel.configuration.guestAdditionsEnabled,
           virtualMachineModel.guestAppSupport != .unsupported
        else { return }

        /// Kick off legacy guest app download if needed.
        if virtualMachineModel.configuration.guestAppVersion != nil {
            Task { try? await guestAppDiskImage.installIfNeeded() }
        }

        let guestDiskState = guestAppDiskImage.state

        logger.info("Guest disk image state is \(guestDiskState, privacy: .public)")

        switch guestDiskState {
        case .ready:
            break
        case .downloading, .installing:
            await waitForGuestDiskImageReady()
        case .installFailed(let error):
            runGuestDiskImageErrorAlert(error: error)
        }
    }

    private func waitForGuestDiskImageReady() async {
        state = .starting("Preparing guest app disk image")

        for await state in guestAppDiskImage.$state.values {
            switch state {
            case .ready:
                logger.debug("Guest disk image is ready 🚀")
                return
            case .installFailed(let error):
                logger.error("Guest disk image install failed - \(error, privacy: .public)")
                return runGuestDiskImageErrorAlert(error: error)
            case .downloading:
                logger.debug("Guest disk image is downloading...")
            case .installing:
                logger.debug("Guest disk image is installing...")
            }
        }
    }

    private func runGuestDiskImageErrorAlert(error: Error) {
        logger.debug(#function)

        let alertSuppressionKey = "VBGuestDiskImageAlertSuppressed"

        guard !UserDefaults.standard.bool(forKey: alertSuppressionKey) else {
            logger.debug("Guest disk image error alert suppressed, ignoring error.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Guest App Image Error"
        alert.informativeText =
        """
        An error occurred when VirtualBuddy attempted to generate the disk image for the guest app. Restarting the app might fix it.
        
        The virtual machine will boot normally, but the guest app disk image will not be mounted.
        
        If the virtual machine already has the guest app installed, it will not be updated to the latest version.
        
        \(error)
        """

        alert.addButton(withTitle: "Continue")
        alert.showsSuppressionButton = true

        alert.runModal()

        if let suppressionButton = alert.suppressionButton,
           suppressionButton.state == .on
        {
            logger.info("Guest disk image error alert will be suppressed in the future.")

            UserDefaults.standard.set(true, forKey: alertSuppressionKey)
        }
    }

    // MARK: Pausing, Stopping

    public func pause() async throws {
        try await lease.perform {
            guard state.canPause else { return }

            do {
                let instance = try ensureInstance()

                try await instance.pause()
                let vm = try instance.virtualMachine

                state = .paused(vm)
            } catch {
                reconcileState(after: error)
                throw error
            }
        }

        unhideCursor()
    }
    
    /// Resumes a paused virtual machine. Starting a virtual machine that has a saved session is done by ``start(discardingSavedSession:)``.
    public func resume() async throws {
        try await lease.perform {
            guard state.canResume else { return }

            do {
                let instance = try ensureInstance()

                try await instance.resume()
                let vm = try instance.virtualMachine

                state = .running(vm)
            } catch {
                reconcileState(after: error)
                throw error
            }

            await finishRestoreIfPending()
        }

        unhideCursor()
    }

    /// Asks the guest to shut down. The state changes once the guest has actually stopped.
    public func stop() async throws {
        try await lease.perform {
            guard state.isRunning else { return }

            do {
                let instance = try ensureInstance()

                try await instance.stop()
            } catch {
                reconcileState(after: error)
                throw error
            }
        }

        unhideCursor()
    }

    /// Asks the guest to shut down and waits until it has. This never turns into a force stop,
    /// however long the guest takes. Cancelling the calling task stops waiting without affecting the guest.
    public func shutDownAndWait() async throws {
        if state.isPaused {
            try await resume()
        }

        try await stop()

        for await state in $state.values {
            try Task.checkCancellation()

            if state.isStopped || state.isIdle || state.isSavedSessionPresentation { return }
        }
    }
    
    /// Terminates the virtual machine immediately. The guest doesn't get a chance to shut down, which can lose data.
    public func forceStop() async throws {
        try await lease.perform {
            guard instance != nil else { return }

            do {
                let instance = try ensureInstance()

                try await instance.forceStop()

                state = .stopped(nil)
            } catch {
                reconcileState(after: error)
                throw error
            }

            await finishRestoreIfPending()
        }

        unhideCursor()
    }

    /// Waits until every operation that's currently in progress or queued has finished.
    public func waitForPendingOperations() async {
        await lease.perform { }
    }

    /// Replaces the running virtual machine's network attachments and starts automatic retries for
    /// any host interfaces that are not available yet.
    public func reconnectNetwork() throws {
        try ensureInstance().reconnectNetwork()
    }

    public var availableBridgeInterfaces: [VBNetworkDeviceInterface] {
        VBNetworkDevice.bridgeInterfaces.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            return nameOrder == .orderedSame ? lhs.id < rhs.id : nameOrder == .orderedAscending
        }
    }

    public var activeBridgeInterfaceIdentifiers: Set<String> {
        instance?.activeBridgeInterfaceIdentifiers ?? []
    }

    @available(macOS 27.0, *)
    public var usbDeviceController: VMUSBDeviceController? {
        instance?.usbDeviceController
    }

    public func changeBridgeInterface(to interfaceIdentifier: String) throws {
        let instance = try ensureInstance()
        objectWillChange.send()
        try instance.changeBridgeInterface(to: interfaceIdentifier)
    }

    // MARK: Saving

    /// Saves the virtual machine's session, then stops it.
    ///
    /// The virtual machine keeps running (or stays paused) if saving fails before the session is complete.
    /// Calling this while a save is already in progress joins it instead of starting another one.
    public func saveAndStop() async throws {
        if let inFlightSave {
            return try await inFlightSave.value
        }

        let task = Task { @MainActor [self] in
            try await lease.perform { try await performSaveAndStop() }
        }

        inFlightSave = task

        defer { inFlightSave = nil }

        try await task.value
    }

    /// Stops a save that hasn't published its session yet. Takes effect at the next safe point.
    public func cancelSave() {
        inFlightSave?.cancel()
    }

    private func performSaveAndStop() async throws {
        guard state.isRunning || state.isPaused else {
            /// A repeated request after the session was saved has nothing left to do.
            if state.isSavedSessionPresentation { return }
            throw SavedSessionError.operationInProgress
        }

        let instance = try ensureInstance()
        let vm = try instance.virtualMachine

        /// Eligibility includes what's known about the running configuration, which is only checked while the virtual machine is running or paused.
        if let issue = saveEligibility.primaryIssue {
            throw SavedSessionError.notEligible(issue)
        }

        state = .saving(vm, .preparing)

        await finishRestoreIfPending()

        let storage = self.storage
        var wasRunning = false
        let descriptor: VBSavedSessionDescriptor

        do {
            try Task.checkCancellation()

            state = .saving(vm, .pausing)
            wasRunning = try await instance.pauseForSaving()

            try Task.checkCancellation()

            let plan = try instance.makeSavedSessionCapturePlan(wasPausedBeforeSave: !wasRunning)

            state = .saving(vm, .cloningStorage)
            let staged = try await performOffMainActor { try storage.stageCapture(plan) }

            do {
                state = .saving(vm, .savingMemory)
                try await instance.saveMachineState(to: staged.stateFileURL)

                try Task.checkCancellation()

                state = .saving(vm, .finalizing)
                descriptor = try await performOffMainActor { try storage.publish(staged) }
            } catch {
                storage.abandon(staged)
                throw error
            }
        } catch {
            logger.error("Saving session failed: \(error, privacy: .public)")

            await returnToConditionBeforeSave(instance: instance, wasRunning: wasRunning)

            throw error
        }

        /// The session is complete and published from here on. It must survive whatever happens next.
        state = .saving(vm, .stopping)

        do {
            try await instance.tearDownAfterSave()
        } catch {
            logger.error("Stopping after save failed: \(error, privacy: .public)")

            virtualMachineModel.reloadSavedSession()
            state = .recoveryRequired(.stopFailedAfterSave(error.localizedDescription))

            throw SavedSessionError.stopFailedAfterSave(error)
        }

        self.instance = nil
        virtualMachineModel.reloadSavedSession()
        state = .saved(virtualMachineModel.savedSession ?? descriptor)
        library.reload(animated: false)

        unhideCursor()
    }

    private func returnToConditionBeforeSave(instance: VMInstance, wasRunning: Bool) async {
        if wasRunning, let vm = try? instance.virtualMachine, vm.state == .paused {
            do {
                try await instance.resume()
            } catch {
                /// The state reported below is the actual one: paused.
                logger.error("Failed to resume after failed save: \(error, privacy: .public)")
            }
        }

        reconcileState()
    }

    /// Tries again to stop a virtual machine whose session was saved but which couldn't be stopped.
    public func retryStopAfterSave() async throws {
        try await lease.perform {
            guard case .recoveryRequired(.stopFailedAfterSave) = state else { return }

            let instance = try ensureInstance()
            try await instance.tearDownAfterSave()

            self.instance = nil
            virtualMachineModel.reloadSavedSession()
            state = restingState
        }
    }

    // MARK: Discarding a Saved Session

    /// Forgets the saved session. The virtual machine's disks are kept as they are, but the running session
    /// is lost, along with any unsaved work in it.
    public func discardSavedSession() async throws {
        try await lease.perform {
            try await discardSavedSessionLocked()
        }
    }

    private func discardSavedSessionLocked() async throws {
        let storage = self.storage

        try await performOffMainActor { try storage.discard() }

        virtualMachineModel.reloadSavedSession()
        library.reload(animated: false)

        if let instance, let vm = try? instance.virtualMachine, vm.state == .paused {
            /// The virtual machine was saved but couldn't be stopped. It's usable again now that the session is gone.
            await instance.restartGuestCommunication()
            state = .paused(vm)
        } else {
            state = restingState
        }
    }

    /// Makes a session that was interrupted after resuming restorable again. Anything that happened since is lost when it's restored.
    public func reinstateInterruptedSavedSession() async throws {
        try await lease.perform {
            let storage = self.storage

            try await performOffMainActor { try storage.reinstateConsumedSession() }

            virtualMachineModel.reloadSavedSession()
            state = restingState
        }
    }

    private func ensureInstance() throws -> VMInstance {
        guard let instance = instance else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        
        instance.options = options
        
        return instance
    }

    public func storeScreenshot(with data: Data) {
        do {
            try virtualMachineModel.write(data, forMetadataFileNamed: VBVirtualMachine.screenshotFileName)
            try virtualMachineModel.invalidateThumbnail()            
        } catch {
            logger.error("Error storing screenshot: \(error)")
        }
    }

    public func invalidate() {
        library.removeController(self)
    }

    deinit {
        #if DEBUG
        print("\(name) Bye bye 👋")
        #endif
        library.removeController(self)

        VBMemoryLeakDebugAssertions.vb_objectIsBeingReleased(self)
    }

}

public extension VMState {

    static func ==(lhs: VMState, rhs: VMState) -> Bool {
        switch lhs {
        case .idle: return rhs.isIdle
        case .starting: return rhs.isStarting
        case .resizingDisk: return rhs.isResizingDisk
        case .running: return rhs.isRunning
        case .paused: return rhs.isPaused
        case .stopped: return rhs.isStopped
        case .saving: return rhs.isSaving
        case .restoring: return rhs.isRestoring
        case .saved: return rhs.isSaved
        case .recoveryRequired: return rhs.isRecoveryRequired
        }
    }

    var isIdle: Bool {
        guard case .idle = self else { return false }
        return true
    }

    var isStarting: Bool {
        guard case .starting = self else { return false }
        return true
    }
    var isResizingDisk: Bool {
        guard case .resizingDisk = self else { return false }
        return true
    }

    var isRunning: Bool {
        guard case .running = self else { return false }
        return true
    }

    var isPaused: Bool {
        guard case .paused = self else { return false }
        return true
    }

    var isStopped: Bool {
        guard case .stopped = self else { return false }
        return true
    }

    var isSaving: Bool {
        guard case .saving = self else { return false }
        return true
    }

    var isRestoring: Bool {
        guard case .restoring = self else { return false }
        return true
    }

    var isSaved: Bool {
        guard case .saved = self else { return false }
        return true
    }

    var isRecoveryRequired: Bool {
        guard case .recoveryRequired = self else { return false }
        return true
    }

    /// `true` while a save or restore operation is in progress.
    var isPerformingSessionOperation: Bool { isSaving || isRestoring }

    /// `true` when the virtual machine isn't running and has a saved session, which can be ready to resume or need a decision.
    var isSavedSessionPresentation: Bool { isSaved || isRecoveryRequired }

    /// `true` when the virtual machine is running, paused, or in the middle of an operation that involves its execution.
    var isActive: Bool {
        switch self {
        case .starting, .resizingDisk, .running, .paused, .saving, .restoring: true
        case .idle, .saved, .recoveryRequired, .stopped: false
        }
    }

    var canStart: Bool {
        switch self {
        case .idle, .stopped, .saved, .recoveryRequired:
            return true
        default:
            return false
        }
    }

    var canSaveAndClose: Bool {
        switch self {
        case .running, .paused:
            return true
        default:
            return false
        }
    }

    var canResume: Bool {
        switch self {
        case .paused:
            return true
        default:
            return false
        }
    }

    var canPause: Bool {
        switch self {
        case .running:
            return true
        default:
            return false
        }
    }

}

public extension VMController {
    
    var canStart: Bool { state.canStart }

    var canResume: Bool { state.canResume }

    var canPause: Bool { state.canPause }

    var canReconnectNetwork: Bool { state.isRunning || state.isPaused }

    var canChangeBridgeInterface: Bool {
        canReconnectNetwork && instance?.hasBridgedNetworkAttachments == true
    }

}

public extension VMController {
    /// Workaround for cursor disappearing due to it being captured
    /// by Virtualization during state transitions.
    func unhideCursor() {
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            NSCursor.unhide()
        }
    }
}

public extension VBMacConfiguration {
    /// DFU mode option is currently shown in debug builds or when `VBShowDFUModeBootOption` is set in user defaults.
    /// To enable in release builds: `defaults write codes.rambo.VirtualBuddy VBShowDFUModeBootOption -bool YES`
    static var appBuildAllowsDFUMode: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "VBShowDFUModeBootOption")
        #endif
    }
}

extension VBMacConfiguration {
    var guestAppDiskImageSource: GuestAdditionsDiskImage.Source {
        if let guestAppVersion {
            GuestAdditionsDiskImage.Source.catalog(guestAppVersion)
        } else {
            GuestAdditionsDiskImage.Source.embedded
        }
    }
}
