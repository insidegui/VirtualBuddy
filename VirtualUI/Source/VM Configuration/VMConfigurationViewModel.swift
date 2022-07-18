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
    
    @Published var selectedDisplayPreset: VBDisplayPreset?
    
    init(config: VBMacConfiguration) {
        self.config = config
    }
    
}
