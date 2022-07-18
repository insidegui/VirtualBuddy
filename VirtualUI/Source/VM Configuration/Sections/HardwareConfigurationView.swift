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

#if DEBUG
struct HardwareConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _Template(hardware: VBMacDevice.default)
    }

    struct _Template: View {
        @State var hardware: VBMacDevice
        init(hardware: VBMacDevice) {
            self._hardware = .init(wrappedValue: hardware)
        }
        var body: some View {
            _ConfigurationSectionPreview {
                HardwareConfigurationView(device: $hardware)
            }
        }
    }
}
#endif
