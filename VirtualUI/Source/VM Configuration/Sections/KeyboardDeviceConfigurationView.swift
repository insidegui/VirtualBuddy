//
//  KeyboardDeviceConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 02/10/23.
//

import SwiftUI
import VirtualCore

struct KeyboardDeviceConfigurationView: View {
    @Binding var hardware: VBMacDevice

    var body: some View {
        PropertyControl("Device Type", spacing: 8) {
            VStack(alignment: .leading) {
                Picker("Device Type", selection: $hardware.keyboardDevice.kind) {
                    ForEach(VBKeyboardDevice.Kind.allCases) { kind in
                        Text(kind.name)
                            .tag(kind)
                    }
                }

                if let error = hardware.keyboardDevice.kind.error {
                    Text(error)
                        .foregroundColor(.red)
                } else if let warning = hardware.keyboardDevice.kind.warning {
                    Text(warning)
                        .foregroundColor(.yellow)
                }
            }
        }

    }
}

#if DEBUG
struct KeyboardDeviceConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview { KeyboardDeviceConfigurationView(hardware: $0.hardware) }
    }
}
#endif
