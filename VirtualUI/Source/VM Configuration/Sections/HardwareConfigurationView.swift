//
//  HardwareConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct HardwareConfigurationView: View {
    
    @Binding var device: VBMacDevice
    
    var body: some View {
        NumericPropertyControl(
            value: $device.cpuCount,
            range: VBMacDevice.virtualCPUCountRange,
            label: "Virtual CPUs",
            formatter: NumberFormatter.numericPropertyControlDefault,
            spacing: VMConfigurationView.labelSpacing
        )

        NumericPropertyControl(
            value: $device.memorySize.gbValue,
            range: VBMacDevice.memorySizeRangeInGigabytes,
            label: "Memory (GB)",
            formatter: NumberFormatter.numericPropertyControlDefault,
            spacing: VMConfigurationView.labelSpacing
        )
    }
    
}
