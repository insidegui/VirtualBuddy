//
//  VMScreenshotter.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 12/04/22.
//

import Foundation
import Virtualization

final class VMScreenshotter {
    
    private weak var instance: VMInstance? {
        didSet {
            Task { self.vmModel = await instance?.virtualMachineModel }
        }
    }
    private var vmModel: VBVirtualMachine?
    private let interval: TimeInterval
    
    init(interval: TimeInterval) {
        assert(interval > 1, "The minimum interval is 1 second")
        
        self.interval = max(1, interval)
    }
    
    private var timer: Timer?
    
    func activate(with instance: VMInstance) {
        invalidate()
        
        self.instance = instance
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { [weak self] _ in
            self?.timerFired()
        })
    }
    
    func invalidate() {
        pendingCapture?.cancel()
        timer?.invalidate()
        timer = nil
        
        if let previousScreenshotData = previousScreenshotData {
            Task {
                try await store(previousScreenshotData)
            }
        }
    }
    
    private func timerFired() {
        capture()
    }
    
    // Used to restore to the second-to-last screenshot when the machine shuts down,
    // so as to avoid having the screenshots all be the same (the Dock moving down and no Menu Bar).
    private var previousScreenshotData: Data?
    
    private var pendingCapture: Task<(), Error>?
    
    func capture() {
        pendingCapture = Task.detached(priority: .utility) { [weak self] in
            guard let self = self, let instance = self.instance else { return }
            
            let shot = try await instance.takeScreenshot()
            
            try Task.checkCancellation()
            
            guard let data = shot.tiffRepresentation(using: .ccittfax4, factor: 0.8) else { return }
            
            self.previousScreenshotData = data
            
            try Task.checkCancellation()
            
            try await self.store(data)
        }
    }
    
    private func store(_ data: Data) async throws {
        guard let vmModel = vmModel else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }

        try await VMLibraryController.shared.write(
            data,
            forMetadataFileNamed: "Screenshot.tiff",
            in: vmModel
        )
    }
    
}
