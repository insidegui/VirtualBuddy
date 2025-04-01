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
    public var stateRestorationPackage: VBSavedStatePackage?

    public static let `default` = VMSessionOptions()

    public init(bootInRecoveryMode: Bool = false, bootInDFUMode: Bool = false, bootOnInstallDevice: Bool = false, autoBoot: Bool = false, stateRestorationPackage: VBSavedStatePackage? = nil) {
        self.bootInRecoveryMode = bootInRecoveryMode
        self.bootInDFUMode = bootInDFUMode
        self.bootOnInstallDevice = bootOnInstallDevice
        self.autoBoot = autoBoot
        self.stateRestorationPackage = stateRestorationPackage

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
    case starting
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
        state = .starting
        
        try await updatingState {
            let newInstance = try createInstance()
            self.instance = newInstance

            if #available(macOS 14.0, *), let restorePackage = options.stateRestorationPackage {
                try await newInstance.restoreState(from: restorePackage) { vm, package in
                    try? await updatingState {
                        state = .restoringState(vm, package)
                    }
                }
            } else {
                try await newInstance.startVM()
            }

            let vm = try newInstance.virtualMachine

            state = .running(vm)
            virtualMachineModel.metadata.installFinished = true
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

            state = .savingState(vm)

            let package = try await instance.saveState(snapshotName: name)

            state = .stateSaveCompleted(vm, package)

            try await Task.sleep(for: .seconds(1.5))

            try await resume()
        }

        unhideCursor()
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
