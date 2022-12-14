//
//  PointingDeviceConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct PointingDeviceConfigurationView: View {
    @Binding var hardware: VBMacDevice
    
    var body: some View {
        PropertyControl("Device Type", spacing: 8) {
            VStack(alignment: .leading) {
                Picker("Device Type", selection: $hardware.pointingDevice.kind) {
                    ForEach(VBPointingDevice.Kind.allCases) { kind in
                        Text(kind.name)
                            .tag(kind)
                    }
                }
                
                if let error = hardware.pointingDevice.kind.error {
                    Text(error)
                        .foregroundColor(.red)
                } else if let warning = hardware.pointingDevice.kind.warning {
                    Text(warning)
                        .foregroundColor(.yellow)
                }
            }
        }

    }
}

#if DEBUG
struct PointingDeviceConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview { PointingDeviceConfigurationView(hardware: $0.hardware) }
    }
}
#endif
