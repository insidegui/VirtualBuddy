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

    /// Used when restoring from a previously-saved state.
    public var stateRestorationPackageURL: URL?

    public static let `default` = VMSessionOptions()

    public init(bootInRecoveryMode: Bool = false, bootInDFUMode: Bool = false, bootOnInstallDevice: Bool = false, autoBoot: Bool = false, stateRestorationPackageURL: URL? = nil) {
        self.bootInRecoveryMode = bootInRecoveryMode
        self.bootInDFUMode = bootInDFUMode
        self.bootOnInstallDevice = bootOnInstallDevice
        self.autoBoot = autoBoot
        self.stateRestorationPackageURL = stateRestorationPackageURL

        resolveMutuallyExclusiveOptions()
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

public enum VMState: Equatable {
    case idle
    case starting(_ message: String?)
    case running(VZVirtualMachine)
    case paused(VZVirtualMachine)
    case savingState(VZVirtualMachine)
    case stateSaveCompleted(VZVirtualMachine, VBSavedStatePackage)
    case restoringState(VZVirtualMachine, VBSavedStatePackage)
    case stopped(Error?)
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
    
    private(set) var virtualMachine: VZVirtualMachine?

    @Published
    public var virtualMachineModel: VBVirtualMachine

    public private(set) var savedStatesController: VMSavedStatesController

    private lazy var cancellables = Set<AnyCancellable>()
    
    public init(with vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions? = nil) {
        self.id = vm.id
        self.name = vm.name
        self.virtualMachineModel = vm
        self.library = library
        self.savedStatesController = VMSavedStatesController(library: library, virtualMachine: vm)
        
        #if DEBUG
        if ProcessInfo.isSwiftUIPreview { self.savedStatesController = .preview }
        #endif

        virtualMachineModel.reloadMetadata()
        if virtualMachineModel.metadata.installImageURL != nil && !virtualMachineModel.metadata.installFinished {
            self.options.bootOnInstallDevice = true
        }

        if let options {
            self.options = options
        }

        /// Ensure configuration is persisted whenever it changes.
        $virtualMachineModel
            .dropFirst()
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
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
            self?.state = .stopped(error)
        })
        
        newInstance.options = options
        
        return newInstance
    }

    public func start() async throws {
        state = .starting(nil)

        await waitForGuestDiskImageReadyIfNeeded()
        
        // Check and resize disk images if needed
        do {
            try await virtualMachineModel.checkAndResizeDiskImages()
        } catch {
            // Log resize errors but don't fail VM start
            NSLog("Warning: Failed to resize disk images: \(error)")
        }

        try await updatingState {
            let newInstance = try createInstance()
            self.instance = newInstance

            if #available(macOS 14.0, *), let restorePackageURL = options.stateRestorationPackageURL {
                do {
                    let package = try VBSavedStatePackage(url: restorePackageURL)
                    try await newInstance.restoreState(from: package) { vm, package in
                        try? await updatingState {
                            state = .restoringState(vm, package)
                        }
                    }
                } catch {
                    guard !(error is CancellationError) else {
                        state = .idle
                        return
                    }
                    throw error
                }
            } else {
                try await newInstance.startVM()
            }

            let vm = try newInstance.virtualMachine

            state = .running(vm)
            virtualMachineModel.metadata.installFinished = true
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
        guard virtualMachineModel.configuration.guestAdditionsEnabled,
           virtualMachineModel.configuration.systemType.supportsGuestApp
        else { return }

        let guestDiskState = GuestAdditionsDiskImage.current.state

        logger.info("Guest disk image state is \(guestDiskState, privacy: .public)")

        switch guestDiskState {
        case .ready:
            break
        case .installing:
            await waitForGuestDiskImageReady()
        case .installFailed(let error):
            runGuestDiskImageErrorAlert(error: error)
        }
    }

    private func waitForGuestDiskImageReady() async {
        state = .starting("Preparing guest app disk image")

        for await state in GuestAdditionsDiskImage.current.$state.values {
            switch state {
            case .ready:
                logger.debug("Guest disk image is ready 🚀")
                return
            case .installFailed(let error):
                logger.error("Guest disk image install failed - \(error, privacy: .public)")
                return runGuestDiskImageErrorAlert(error: error)
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

    public func pause() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.pause()
            let vm = try instance.virtualMachine

            state = .paused(vm)
        }

        unhideCursor()
    }
    
    public func resume() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.resume()
            let vm = try instance.virtualMachine

            state = .running(vm)
        }

        unhideCursor()
    }
    
    public func stop() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.stop()
        }

        unhideCursor()
    }
    
    public func forceStop() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.forceStop()

            state = .stopped(nil)
        }

        unhideCursor()
    }

    @available(macOS 14.0, *)
    public func saveState(snapshotName name: String) async throws {
        try await updatingState {
            let instance = try ensureInstance()
            let vm = try instance.virtualMachine

            do {
                let package = try await instance.saveState(snapshotName: name) {
                    state = .savingState(vm)
                }

                state = .stateSaveCompleted(vm, package)
            } catch is CancellationError {
                /// User cancellation is not an error, it may just be ignored here.
                /// As of the current implementation of `VMInstance.saveState`, the VM won't be paused
                /// because the only cancellation point is before that happens, but check for pause in here just in
                /// case that behavior changes in the future.
                try await resumeIfNeeded()
            } catch {
                throw error
            }

            try await resumeIfNeeded()
        }

        unhideCursor()
    }

    private func resumeIfNeeded() async throws {
        guard !state.isRunning else { return }

        try await Task.sleep(for: .seconds(1.5))

        try await resume()
    }

    private func updatingState(perform block: () async throws -> Void) async throws {
        do {
            try await block()
        } catch {
            state = .stopped(error)
            throw error
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
        case .running: return rhs.isRunning
        case .paused: return rhs.isPaused
        case .stopped: return rhs.isStopped
        case .savingState: return rhs.isSavingState
        case .restoringState: return rhs.isRestoringState
        case .stateSaveCompleted: return rhs.isStateSaveCompleted
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

    var isSavingState: Bool {
        guard case .savingState = self else { return false }
        return true
    }

    var isRestoringState: Bool {
        guard case .restoringState = self else { return false }
        return true
    }

    var isStateSaveCompleted: Bool {
        guard case .stateSaveCompleted = self else { return false }
        return true
    }

    var canStart: Bool {
        switch self {
        case .idle, .stopped:
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
