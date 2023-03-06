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
    
    @DecodableDefault.False
    public var bootOnInstallDevice = false
    
    public static let `default` = VMSessionOptions()
}

@MainActor
public final class VMController: ObservableObject {
    
    private lazy var logger = Logger(for: Self.self)
    
    @Published
    public var options = VMSessionOptions.default {
        didSet {
            instance?.options = options
        }
    }
    
    public enum State {
        case idle
        case starting
        case running(VZVirtualMachine)
        case paused(VZVirtualMachine)
        case stopped(Error?)
    }
    
    @Published
    public private(set) var state = State.idle {
        didSet { updateScreenshotter() }
    }
    
    private(set) var virtualMachine: VZVirtualMachine?

    @Published
    public var virtualMachineModel: VBVirtualMachine

    private lazy var cancellables = Set<AnyCancellable>()
    
    public init(with vm: VBVirtualMachine) {
        self.virtualMachineModel = vm
        virtualMachineModel.reloadMetadata()
        if virtualMachineModel.metadata.installImageURL != nil && !virtualMachineModel.metadata.installFinished {
            options.bootOnInstallDevice = true
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
    }

    private var instance: VMInstance?
    
    private func createInstance() throws -> VMInstance {
        let newInstance = VMInstance(with: virtualMachineModel, onVMStop: { [weak self] error in
            self?.state = .stopped(error)
        })
        
        newInstance.options = options
        
        return newInstance
    }
    
    private lazy var screenshotter = VMScreenshotter(interval: 15)

    public func startVM() async {
        state = .starting
        
        do {
            let newInstance = try createInstance()
            self.instance = newInstance

            try await newInstance.startVM()
            let vm = try newInstance.virtualMachine
            
            state = .running(vm)
            virtualMachineModel.metadata.installFinished = true
        } catch {
            state = .stopped(error)
        }
    }
    
    public func pause() async throws {
        screenshotter.capture()
        
        let instance = try ensureInstance()
        
        try await instance.pause()
        let vm = try instance.virtualMachine
        
        state = .paused(vm)
    }
    
    public func resume() async throws {
        let instance = try ensureInstance()
        
        try await instance.resume()
        let vm = try instance.virtualMachine
        
        state = .running(vm)
    }
    
    public func stop() async throws {
        screenshotter.capture()
        
        let instance = try ensureInstance()
        
        try await instance.stop()
        
        state = .stopped(nil)
    }
    
    public func forceStop() async throws {
        screenshotter.capture()
        
        let instance = try ensureInstance()
        
        try await instance.forceStop()
        
        state = .stopped(nil)
    }
    
    private func ensureInstance() throws -> VMInstance {
        guard let instance = instance else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        
        instance.options = options
        
        return instance
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

private extension VMController {
    
    func updateScreenshotter() {
        switch state {
        case .idle, .paused, .stopped, .starting:
            screenshotter.invalidate()
        case .running:
            guard let instance = try? ensureInstance() else { return }
            
            screenshotter.activate(with: instance)
        }
    }
    
}
