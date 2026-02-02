//
//  DisplayConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct DisplayConfigurationView: View {
    
    @Binding var device: VBDisplayDevice
    @Binding var selectedPreset: VBDisplayPreset?
    var canChangePPI: Bool

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    private var displayResizeStatus: ResolvedFeatureStatus? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.displayResize)?.status
    }

    private var displayResizeUnsupported: Bool { displayResizeStatus?.isUnsupported == true }
    
    var body: some View {
        if let warning = selectedPreset?.warning {
            Text(warning)
                .foregroundColor(.yellow)
                .padding(.bottom, 8)
        }
        
        NumericPropertyControl(
            value: $device.width,
            range: VBDisplayDevice.displayWidthRange,
            label: "Width (Pixels)",
            formatter: NumberFormatter.numericPropertyControlDefault,
            spacing: VMConfigurationView.labelSpacing
        )

        NumericPropertyControl(
            value: $device.height,
            range: VBDisplayDevice.displayHeightRange,
            label: "Height (Pixels)",
            formatter: NumberFormatter.numericPropertyControlDefault,
            spacing: VMConfigurationView.labelSpacing
        )

        if canChangePPI {
            NumericPropertyControl(
                value: $device.pixelsPerInch,
                range: VBDisplayDevice.displayPPIRange,
                label: "Pixels Per Inch",
                formatter: NumberFormatter.numericPropertyControlDefault,
                spacing: VMConfigurationView.labelSpacing
            )
        }
        
        if VBDisplayDevice.automaticallyReconfiguresDisplaySupportedByHost {
            Group {
                if displayResizeUnsupported {
                    let helpMessage = displayResizeStatus?.supportMessage ?? "Not supported."
                    Toggle("Automatically Configure Display", isOn: $device.automaticallyReconfiguresDisplay)
                        .disabled(true)
                        .help(helpMessage)
                } else {
                    Toggle("Automatically Configure Display", isOn: $device.automaticallyReconfiguresDisplay)
                }
            }
            .onChange(of: displayResizeUnsupported) { isUnsupported in
                if isUnsupported {
                    device.automaticallyReconfiguresDisplay = false
                }
            }
            .onAppear {
                if displayResizeUnsupported {
                    device.automaticallyReconfiguresDisplay = false
                }
            }
        }
    }
    
    @ViewBuilder
    var presetPicker: some View {
        DisplayPresetPicker(display: $device, selection: $selectedPreset)
    }
    
}

private struct DisplayPresetPicker: View {

    @Binding var display: VBDisplayDevice
    @Binding var selection: VBDisplayPreset?
    @State private var presets = [VBDisplayPreset]()

    @Environment(\.configurationGuestType)
    private var guestType: VBGuestType

    var body: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "wand.and.stars")
                .foregroundColor(.accentColor)
        }
        .menuStyle(.borderlessButton)
        .help("Display Suggestions")
        .onAppear {
            presets = VBDisplayPreset.availablePresets(for: guestType)
        }
    }
    
    @ViewBuilder
    var menuItems: some View {
        ForEach(presets) { preset in
            Button(preset.name) {
                selection = preset
                display = preset.device
            }
        }
    }
    
}

#if DEBUG
struct DisplayConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview {
            DisplayConfigurationView(device: $0.hardware.displayDevices[0], selectedPreset: .constant(nil), canChangePPI: true)
        }
    }
}
#endif
