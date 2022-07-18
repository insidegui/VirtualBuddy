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
        _Template(hardware: VBMacDevice.default)
    }

    struct _Template: View {
        @State var hardware: VBMacDevice
        init(hardware: VBMacDevice) {
            self._hardware = .init(wrappedValue: hardware)
        }
        var body: some View {
            ConfigurationSection({
                SoundConfigurationView(hardware: $hardware)
            }, header: {
                Label("Sound", systemImage: "speaker.3")
            })

            .frame(maxWidth: 320, maxHeight: .infinity, alignment: .top)
                .padding()
                .controlGroup()
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
