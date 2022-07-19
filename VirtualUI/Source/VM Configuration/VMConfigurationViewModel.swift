//
//  VMConfigurationViewModel.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

public final class VMConfigurationViewModel: ObservableObject {
    
    @Published var config: VBMacConfiguration {
        didSet {
            /// Reset display preset when changing display settings.
            /// This is so the warning goes away, if any warning is being shown.
            if config.hardware.displayDevices != oldValue.hardware.displayDevices,
               config.hardware.displayDevices.first != selectedDisplayPreset?.device
            {
                selectedDisplayPreset = nil
            }
        }
    }
    
    @Published public internal(set) var supportState: VBMacConfiguration.SupportState = .supported
    
    @Published var selectedDisplayPreset: VBDisplayPreset?
    
    @Published private(set) var vm: VBVirtualMachine
    
    public init(_ vm: VBVirtualMachine) {
        self.config = vm.configuration
        self.vm = vm
        
        Task { await commitConfiguration() }
    }

    @discardableResult
    public func commitConfiguration(createDiskImages: Bool = false) async -> VBMacConfiguration.SupportState {
        let imageErrors: [String]

        if createDiskImages {
            imageErrors = await createMissingDiskImagesReturningErrors()
        } else {
            imageErrors = []
        }

        let updatedState: VBMacConfiguration.SupportState

        if imageErrors.isEmpty {
            updatedState = await config.validate(for: vm)
        } else {
            updatedState = .unsupported(imageErrors)
        }

        await MainActor.run {
            supportState = updatedState
        }

        return updatedState
    }

    private func createMissingDiskImagesReturningErrors() async -> [String] {
        var errors: [String] = []

        for device in config.hardware.storageDevices {
            do {
                try await device.createDiskImageIfNeeded(for: vm)
            } catch {
                errors.append("Error creating disk image for \"\(device.name)\": \(error.localizedDescription)")
            }
        }

        return errors
    }
    
}
