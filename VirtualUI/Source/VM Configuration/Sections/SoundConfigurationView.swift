//
//  SoundConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore
import ManagedPreferencesUI

struct SoundConfigurationView: View {
    @Binding var hardware: VBMacDevice

    @ManagedValue(for: .disableMicrophoneInput, schema: VirtualBuddyManagedPreferences.schema, default: false)
    private var microphoneInputDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Sound", isOn: soundEnabled)

            if hardware.soundDevices.isEmpty || microphoneInputDisabled {
                Toggle("Enable Sound Input", isOn: .constant(false))
                    .disabled(true)
            } else {
                Toggle("Enable Sound Input", isOn: $hardware.soundDevices[0].enableInput)
            }
            if microphoneInputDisabled {
                ManagedRestrictionBannerView(title: "Microphone input is disabled by your organization.")
                Text("Restart the VM to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
