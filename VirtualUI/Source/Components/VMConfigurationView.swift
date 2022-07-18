//
//  VMConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI
import VirtualCore

final class VMConfigurationViewModel: ObservableObject {
    
    @Published var config: VBMacConfiguration {
        didSet {
            /// Reset display preset when changing display settings.
            /// This is so the warning goes away, if any warning is being shown.
            if config.hardware.displayDevices != oldValue.hardware.displayDevices,
               config.hardware.displayDevices.first != selectedDisplayPreset?.device
            {
                selectedDisplayPreset = nil
            }
        }
    }
    
    @Published var selectedDisplayPreset: VBDisplayPreset?
    
    init(config: VBMacConfiguration) {
        self.config = config
    }
    
}

public struct VMConfigurationSheet: View {
    
    @StateObject private var viewModel: VMConfigurationViewModel
    
    /// The VM configuration as it existed when the user opened the configuration UI.
    /// Can be used to reset aspects of the configuration to their previous values.
    private var initialConfiguration: VBMacConfiguration
    
    /// The configuration that gets saved with the VM.
    /// Setting this saves the configuration.
    @Binding private var savedConfiguration: VBMacConfiguration
    
    /// Initializes the VM configuration sheet, bound to a VM configuration model.
    /// - Parameter configuration: The binding that will be updated when the user saves the configuration by clicking the "Done" button.
    public init(configuration: Binding<VBMacConfiguration>) {
        self.initialConfiguration = configuration.wrappedValue
        self._savedConfiguration = configuration
        self._viewModel = .init(wrappedValue: VMConfigurationViewModel(config: configuration.wrappedValue))
    }
    
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        ScrollView(.vertical) {
            VMConfigurationView(initialConfiguration: initialConfiguration)
                .environmentObject(viewModel)
                .padding()
        }
        .safeAreaInset(edge: .bottom) {
            buttons
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var buttons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button("Done") {
                savedConfiguration = viewModel.config
                
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Material.regular, in: Rectangle())
        .overlay(alignment: .top) { Divider() }
    }
    
}

struct VMConfigurationView: View {
    @EnvironmentObject var controller: VMController
    @EnvironmentObject private var viewModel: VMConfigurationViewModel
    
    var initialConfiguration: VBMacConfiguration

    static var labelSpacing: CGFloat { 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            general
            network
            display
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private var general: some View {
        ConfigurationSection {
            NumericPropertyControl(
                value: $viewModel.config.hardware.cpuCount,
                range: VBMacDevice.virtualCPUCountRange,
                step: 1,
                label: "Virtual CPUs",
                formatter: NumberFormatter.numericPropertyControlDefault,
                spacing: Self.labelSpacing
            )

            NumericPropertyControl(
                value: $viewModel.config.hardware.memorySize.gbValue,
                range: VBMacDevice.memorySizeRangeInGigabytes,
                step: VBMacDevice.memorySizeRangeInGigabytes.upperBound / 16,
                label: "Memory (GB)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                spacing: Self.labelSpacing
            )
        } header: {
            Label("General", systemImage: "memorychip")
        }
        .contextMenu {
            Button("Reset General Settings") {
                viewModel.config.hardware.cpuCount = initialConfiguration.hardware.cpuCount
                viewModel.config.hardware.memorySize = initialConfiguration.hardware.memorySize
            }
        }
    }

    @ViewBuilder
    private var display: some View {
        ConfigurationSection {
            if let warning = viewModel.selectedDisplayPreset?.warning {
                Text(warning)
                    .foregroundColor(.yellow)
                    .padding(.bottom, 8)
            }
            
            NumericPropertyControl(
                value: $viewModel.config.hardware.displayDevices[0].width,
                range: VBDisplayDevice.displayWidthRange,
                label: "Width (Pixels)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                spacing: Self.labelSpacing
            )

            NumericPropertyControl(
                value: $viewModel.config.hardware.displayDevices[0].height,
                range: VBDisplayDevice.displayHeightRange,
                label: "Height (Pixels)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                spacing: Self.labelSpacing
            )

            NumericPropertyControl(
                value: $viewModel.config.hardware.displayDevices[0].pixelsPerInch,
                range: VBDisplayDevice.displayPPIRange,
                label: "Pixels Per Inch",
                formatter: NumberFormatter.numericPropertyControlDefault,
                spacing: Self.labelSpacing
            )
        } header: {
            HStack {
                Label("Display", systemImage: "display")
                
                DisplayPresetPicker(
                    display: $viewModel.config.hardware.displayDevices[0],
                    selection: $viewModel.selectedDisplayPreset
                )
                    .frame(width: 24)
            }
        }
    }
    
    @ViewBuilder
    private var network: some View {
        ConfigurationSection {
            NetworkDeviceEditor(device: $viewModel.config.hardware.networkDevices[0])
        } header: {
            Label("Network", systemImage: "network")
        }
    }
}

struct NetworkDeviceEditor: View {
    
    @Binding var device: VBNetworkDevice
    
    var body: some View {
        typePicker
            .padding(.bottom, 8)
        
        VStack(alignment: .leading, spacing: 4) {
            PropertyControlLabel("MAC Address")
            EphemeralTextField($device.macAddress, alignment: .leading) { addr in
                Text(addr)
                    .textCase(.uppercase)
            } editableContent: { value in
                TextField("", text: .init(get: {
                    value.wrappedValue.uppercased()
                }, set: { value.wrappedValue = $0.uppercased() }))
            } validate: { value in
                return VBNetworkDevice.validateMAC(value)
            }
        }
    }
    
    @ViewBuilder
    private var typePicker: some View {
        Picker("Type", selection: $device.kind) {
            ForEach(VBNetworkDevice.Kind.allCases) { kind in
                Text(kind.name)
                    .tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("The type of network device")
    }
    
}

struct DisplayPresetPicker: View {
    
    @Binding var display: VBDisplayDevice
    @Binding var selection: VBDisplayPreset?
    @State private var presets = [VBDisplayPreset]()
    
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
            presets = VBDisplayPreset.availablePresets
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
            PreviewSheet {
                VMConfigurationSheet(configuration: $controller.virtualMachineModel.configuration)
                    .environmentObject(controller)
                    .frame(width: 320, height: 600, alignment: .top)
            }
        }
    }
}

/// Simulates a macOS sheet for SwiftUI previews.
struct PreviewSheet<Content: View>: View {
    var content: () -> Content
    
    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        ZStack {}
        .frame(width: 500, height: 700)
        .background(Color.black.opacity(0.5))
        .overlay {
            content()
                .controlGroup()
        }
    }
}
#endif
