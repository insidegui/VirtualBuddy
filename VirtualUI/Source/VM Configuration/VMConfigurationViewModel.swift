//
//  VMConfigurationViewModel.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

final class VMConfigurationViewModel: ObservableObject {
    
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
    
    @Published var supportState: VBMacConfiguration.SupportState = .supported
    
    @Published var selectedDisplayPreset: VBDisplayPreset?
    
    @Published private(set) var vm: VBVirtualMachine
    
    init(config: VBMacConfiguration, vm: VBVirtualMachine) {
        self.config = config
        self.vm = vm
        
        Task { await updateSupportState() }
    }

    @discardableResult
    func updateSupportState() async -> VBMacConfiguration.SupportState {
        let updatedState = await config.validate(for: vm)
        await MainActor.run {
            supportState = updatedState
        }
        return updatedState
    }
    
}
