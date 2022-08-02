//
//  VMConfigurationSheet.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

public struct VMConfigurationSheet: View {
    
    @EnvironmentObject private var viewModel: VMConfigurationViewModel
    
    /// The VM configuration as it existed when the user opened the configuration UI.
    /// Can be used to reset aspects of the configuration to their previous values.
    private var initialConfiguration: VBMacConfiguration
    
    /// The configuration that gets saved with the VM.
    /// Setting this saves the configuration.
    @Binding private var savedConfiguration: VBMacConfiguration

    @State private var showingValidationErrors = false
    
    private var showsCancelButton: Bool { viewModel.context == .postInstall }
    private var customConfirmationButtonAction: ((VBMacConfiguration) -> Void)? = nil
    
    /// Initializes the VM configuration sheet, bound to a VM configuration model.
    /// - Parameter configuration: The binding that will be updated when the user saves the configuration by clicking the "Done" button.
    public init(configuration: Binding<VBMacConfiguration>) {
        self.init(configuration: configuration, showingValidationErrors: false)
    }
    
    init(configuration: Binding<VBMacConfiguration>, showingValidationErrors: Bool = false, customConfirmationButtonAction: ((VBMacConfiguration) -> Void)? = nil) {
        self.initialConfiguration = configuration.wrappedValue
        self._savedConfiguration = configuration
        self._showingValidationErrors = .init(wrappedValue: showingValidationErrors)
        self.customConfirmationButtonAction = customConfirmationButtonAction
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
        .frame(minWidth: Self.defaultWidth, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity, alignment: .top)
    }
    
    public static let defaultWidth: CGFloat = 370
    
    @ViewBuilder
    private var buttons: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showingValidationErrors {
                validationErrors
            }
            HStack {
                if showsCancelButton {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                
                Spacer()
                
                Button(viewModel.context == .preInstall ? "Continue" : "Done") {
                    validateAndSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(showingValidationErrors)
                .controlSize(viewModel.context == .preInstall ? .large : .regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Material.regular, in: Rectangle())
        .overlay(alignment: .top) { Divider() }
        .onChange(of: viewModel.config) { newValue in
            guard showingValidationErrors else { return }
            
            Task {
                if await viewModel.validate() == .supported {
                    showingValidationErrors = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var validationErrors: some View {
        if viewModel.supportState != .supported {
            VStack(alignment: .leading, spacing: 4) {
                switch viewModel.supportState {
                case .supported:
                    EmptyView()
                case .unsupported(let errors):
                    ForEach(errors, id: \.self) { Text($0) }
                        .foregroundColor(.red)
                case .warnings(let warnings):
                    ForEach(warnings, id: \.self) { Text($0) }
                        .foregroundColor(.yellow)
                }
            }
        }
    }
    
    private func validateAndSave() {
        showingValidationErrors = true

        Task {
            let state = await viewModel.validate()
            
            guard state.allowsSaving else { return }
            
            savedConfiguration = viewModel.config
            
            if let customConfirmationButtonAction {
                customConfirmationButtonAction(savedConfiguration)
            } else {
                dismiss()
            }
        }
    }
    
}

#if DEBUG
struct VMConfigurationSheet_Previews: PreviewProvider {
    static var previews: some View {
        _Template(context: .postInstall)
            .previewDisplayName("Post Install")

        _Template(context: .preInstall)
            .previewDisplayName("Pre Install")
    }

    struct _Template: View {
        @State private var vm = VBVirtualMachine.preview
        var context: VMConfigurationContext

        var body: some View {
            if context == .postInstall {
                PreviewSheet {
                    VMConfigurationSheet(configuration: $vm.configuration)
                        .environmentObject(VMConfigurationViewModel(vm, context: context))
                        .frame(width: 360, height: 600, alignment: .top)
                }
            } else {
                VMConfigurationSheet(configuration: $vm.configuration)
                    .environmentObject(VMConfigurationViewModel(vm, context: context))
                    .frame(width: 360, height: 600, alignment: .top)
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
