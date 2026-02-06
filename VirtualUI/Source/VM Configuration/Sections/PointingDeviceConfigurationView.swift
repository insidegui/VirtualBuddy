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

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    private var trackpadFeature: ResolvedVirtualizationFeature? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.trackpad)
    }

    private var trackpadStatus: ResolvedFeatureStatus? { trackpadFeature?.status }

    private var trackpadUnsupported: Bool { trackpadStatus?.isUnsupported == true }

    private var availableKinds: [VBPointingDevice.Kind] {
        VBPointingDevice.Kind.allCases.filter { kind in
            kind != .trackpad || !trackpadUnsupported
        }
    }
    
    var body: some View {
        PropertyControl("Device Type", spacing: 8) {
            VStack(alignment: .leading) {
                Picker("Device Type", selection: $hardware.pointingDevice.kind) {
                    ForEach(availableKinds) { kind in
                        Text(kind.name)
                            .tag(kind)
                    }
                }
                .onChange(of: trackpadUnsupported) { isUnsupported in
                    if isUnsupported, hardware.pointingDevice.kind == .trackpad {
                        hardware.pointingDevice.kind = .mouse
                    }
                }
                .onAppear {
                    if trackpadUnsupported, hardware.pointingDevice.kind == .trackpad {
                        hardware.pointingDevice.kind = .mouse
                    }
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
