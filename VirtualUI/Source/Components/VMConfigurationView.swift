//
//  VMConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI
import VirtualCore

final class VMConfigurationViewModel: ObservableObject {
    
    @Published var config: VBMacConfiguration
    
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
    
    var unfocusActiveField = VoidSubject()

    var body: some View {
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
                value: $viewModel.config.hardware.cpuCount,
                range: VBMacDevice.virtualCPUCountRange,
                step: 1,
                label: "Virtual CPUs",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )

            NumericPropertyControl(
                value: $viewModel.config.hardware.memorySize.gbValue,
                range: VBMacDevice.memorySizeRangeInGigabytes,
                step: VBMacDevice.memorySizeRangeInGigabytes.upperBound / 16,
                label: "Memory (GB)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
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
            NumericPropertyControl(
                value: $viewModel.config.hardware.displayDevices[0].width,
                range: VBDisplayDevice.displayWidthRange,
                label: "Width (Pixels)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )

            NumericPropertyControl(
                value: $viewModel.config.hardware.displayDevices[0].height,
                range: VBDisplayDevice.displayHeightRange,
                label: "Height (Pixels)",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )

            NumericPropertyControl(
                value: $viewModel.config.hardware.displayDevices[0].pixelsPerInch,
                range: VBDisplayDevice.displayPPIRange,
                label: "Pixels Per Inch",
                formatter: NumberFormatter.numericPropertyControlDefault,
                unfocus: unfocusActiveField
            )
        } header: {
            HStack {
                Label("Display", systemImage: "display")
                
                DisplayPresetPicker(display: $viewModel.config.hardware.displayDevices[0])
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
            PreviewSheet {
                VMConfigurationSheet(configuration: $controller.virtualMachineModel.configuration)
                    .environmentObject(controller)
                    .frame(width: 320, height: 400, alignment: .top)
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
        .frame(width: 500, height: 500)
        .background(Color.black.opacity(0.5))
        .overlay {
            content()
                .controlGroup()
        }
    }
}
#endif
