//
//  SoundConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct SoundConfigurationView: View {
    @Binding var hardware: VBMacDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Sound", isOn: soundEnabled)

            if hardware.soundDevices.isEmpty {
                Toggle("Enable Sound Input", isOn: .constant(false))
                    .disabled(true)
            } else {
                Toggle("Enable Sound Input", isOn: $hardware.soundDevices[0].enableInput)
            }
        }
    }

    private var soundEnabled: Binding<Bool> {
        .init(get: {
            !hardware.soundDevices.isEmpty
        }, set: { newValue in
            if newValue, hardware.soundDevices.isEmpty {
                hardware.soundDevices = [.default]
            } else {
                hardware.soundDevices.removeAll()
            }
        })
    }
}

#if DEBUG
struct SoundConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview { SoundConfigurationView(hardware: $0.hardware) }
    }

}
#endif
