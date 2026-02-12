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

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    private var macKeyboardFeature: ResolvedVirtualizationFeature? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.macKeyboard)
    }

    private var macKeyboardStatus: ResolvedFeatureStatus? { macKeyboardFeature?.status }

    private var macKeyboardUnsupported: Bool { macKeyboardStatus?.isUnsupported == true }

    private var availableKinds: [VBKeyboardDevice.Kind] {
        VBKeyboardDevice.Kind.allCases.filter { kind in
            kind != .mac || !macKeyboardUnsupported
        }
    }

    var body: some View {
        PropertyControl("Device Type", spacing: 8) {
            VStack(alignment: .leading) {
                Picker("Device Type", selection: $hardware.keyboardDevice.kind) {
                    ForEach(availableKinds) { kind in
                        Text(kind.name)
                            .tag(kind)
                    }
                }
                .onChange(of: macKeyboardUnsupported) { isUnsupported in
                    if isUnsupported, hardware.keyboardDevice.kind == .mac {
                        hardware.keyboardDevice.kind = .generic
                    }
                }
                .onAppear {
                    if macKeyboardUnsupported, hardware.keyboardDevice.kind == .mac {
                        hardware.keyboardDevice.kind = .generic
                    }
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
