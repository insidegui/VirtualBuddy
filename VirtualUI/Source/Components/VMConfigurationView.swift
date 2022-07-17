//
//  VMConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI
import VirtualCore

public struct VMConfigurationView: View {
    @EnvironmentObject var controller: VMController

    @Binding var configuration: VBMacConfiguration
    @Binding var hardware: VBMacDevice

    private var unfocusActiveField = VoidSubject()

    public init(configuration: Binding<VBMacConfiguration>, hardware: Binding<VBMacDevice>) {
        self._configuration = configuration
        self._hardware = hardware
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NumericPropertyControl(
                value: $hardware.cpuCount,
                range: VBMacDevice.virtualCPUCountRange,
                step: 1,
                label: "Virtual CPUs",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )

            NumericPropertyControl(
                value: $hardware.memorySize.gbValue,
                range: VBMacDevice.memorySizeRangeInGigabytes,
                step: VBMacDevice.memorySizeRangeInGigabytes.upperBound / 16,
                label: "Memory (GB)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )
        }
    }
}

#if DEBUG
struct VMConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }

    struct _Template: View {
        @StateObject var controller = VMController(with: .preview)

        var body: some View {
            VMConfigurationView(configuration: $controller.virtualMachineModel.configuration, hardware: $controller.virtualMachineModel.configuration.hardware)
                .environmentObject(controller)
                .padding()
        }
    }
}

#endif
