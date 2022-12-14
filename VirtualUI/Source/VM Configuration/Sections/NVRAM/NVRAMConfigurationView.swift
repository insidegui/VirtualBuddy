//
//  SharingConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct NVRAMConfigurationView: View {
    @Binding var hardware: VBMacDevice

    var body: some View {
        NVRAMManagementView(
          hardware: $hardware
        )
    }
}

#if DEBUG
struct NVRAMConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
      _ConfigurationSectionPreview { NVRAMConfigurationView(hardware: $0.hardware) }

      _ConfigurationSectionPreview(.preview.removingNVRAM) { NVRAMConfigurationView(hardware: $0.hardware) }
            .previewDisplayName("Empty")
    }
}
#endif
