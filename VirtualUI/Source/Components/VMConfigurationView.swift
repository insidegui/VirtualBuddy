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
        VStack(alignment: .leading, spacing: 16) {
            general
            display
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private var general: some View {
        ConfigurationSection {
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
        } header: {
            Label("General", systemImage: "memorychip")
        }
    }

    @ViewBuilder
    private var display: some View {
        ConfigurationSection {
            NumericPropertyControl(
                value: $hardware.displayDevices[0].width,
                range: VBDisplayDevice.displayWidthRange,
                label: "Width (Pixels)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )

            NumericPropertyControl(
                value: $hardware.displayDevices[0].height,
                range: VBDisplayDevice.displayHeightRange,
                label: "Height (Pixels)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )

            NumericPropertyControl(
                value: $hardware.displayDevices[0].pixelsPerInch,
                range: VBDisplayDevice.displayPPIRange,
                label: "Pixels Per Inch",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )
        } header: {
            HStack {
                Label("Display", systemImage: "display")
                
                DisplayPresetPicker(display: $hardware.displayDevices[0])
                    .frame(width: 24)
            }
        }
    }
}

struct DisplayPresetPicker: View {
    
    @Binding var display: VBDisplayDevice
    @State private var presets = [DisplayPreset]()
    
    var body: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "lightbulb.fill")
        }
        .menuStyle(.borderlessButton)
        .help("Display Suggestions")
        .onAppear {
            presets = DisplayPreset.availablePresets
        }
    }
    
    @ViewBuilder
    var menuItems: some View {
        ForEach(presets) { preset in
            Button(preset.name) {
                display = preset.device
            }
        }
    }
    
}

struct ConfigurationSection<Header: View, Content: View>: View {

    @State private var isCollapsed = false

    var content: () -> Content
    var header: () -> Header

    init(@ViewBuilder _ content: @escaping () -> Content, @ViewBuilder header: @escaping () -> Header) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            styledHeader

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                    .padding()
                    .transition(.opacity)
            }
        }
        .controlGroup()
    }

    @ViewBuilder
    private var styledHeader: some View {
        HStack {
            header()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
        }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.ultraThick, in: Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .frame(maxWidth: .infinity, maxHeight: 0.5)
                    .foregroundColor(.black.opacity(isCollapsed ? 0 : 0.5))
            }
            .onTapGesture {
                withAnimation(.default) {
                    isCollapsed.toggle()
                }
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
                .frame(width: 320, height: 400, alignment: .top)
                .padding()
                .padding(50)
        }
    }
}

#endif
