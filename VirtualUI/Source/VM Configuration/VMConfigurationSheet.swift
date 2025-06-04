//
//  VMConfigurationSheet.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

public struct VMConfigurationSheet: View {

    public static let minWidth: CGFloat = 520

    @EnvironmentObject private var viewModel: VMConfigurationViewModel
    
    /// The VM configuration as it existed when the user opened the configuration UI.
    /// Can be used to reset aspects of the configuration to their previous values.
    private var initialConfiguration: VBMacConfiguration
    
    /// The configuration that gets saved with the VM.
    /// Setting this saves the configuration.
    @Binding private var savedConfiguration: VBMacConfiguration

    @State private var showValidationErrors = false
    
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
        self._showValidationErrors = .init(wrappedValue: showingValidationErrors)
        self.customConfirmationButtonAction = customConfirmationButtonAction
    }
    
    @Environment(\.dismiss) private var dismiss

    @Environment(\.containerPadding) private var containerPadding
    @Environment(\.maxContentWidth) private var maxContentWidth

    private var isInstall: Bool { viewModel.context == .preInstall }

    public var body: some View {
        ScrollView(.vertical) {
            VMConfigurationView(initialConfiguration: initialConfiguration)
                .environmentObject(viewModel)
                .frame(maxWidth: isInstall ? maxContentWidth : nil)
                .padding(containerPadding)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isInstall { buttons }
        }
        .resizableSheet(minWidth: Self.minWidth, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showValidationErrors {
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
                .disabled(showValidationErrors)
                .controlSize(viewModel.context == .preInstall ? .large : .regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Material.regular, in: Rectangle())
        .overlay(alignment: .top) { Divider() }
        .onChange(of: viewModel.config) { newValue in
            guard showValidationErrors else { return }
            
            Task {
                if await viewModel.validate() == .supported {
                    showValidationErrors = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var validationErrors: some View {
        if case .unsupported(let errors) = viewModel.supportState {
            ForEach(errors, id: \.self) { Text($0) }
                .foregroundColor(.red)
        }
    }
    
    private func validateAndSave() {
        showValidationErrors = true

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
        _Template(vm: .preview, context: .preInstall)
            .previewDisplayName("Pre Install")

        _Template(vm: .preview, context: .postInstall)
            .previewDisplayName("Post Install")

        _Template(vm: .previewLinux, context: .postInstall)
            .previewDisplayName("Linux - Post")

        _Template(vm: .previewLinux, context: .preInstall)
            .previewDisplayName("Linux - Pre")
    }

    struct _Template: View {
        @State var vm: VBVirtualMachine
        var context: VMConfigurationContext

        var body: some View {
            if context == .postInstall {
                PreviewSheet {
                    VMConfigurationSheet(configuration: $vm.configuration)
                        .environmentObject(VMConfigurationViewModel(vm, context: context))
                        .frame(width: VMConfigurationSheet.minWidth, height: 600, alignment: .top)
                }
            } else {
                VMConfigurationSheet(configuration: $vm.configuration)
                    .environmentObject(VMConfigurationViewModel(vm, context: context))
                    .frame(width: VMConfigurationSheet.minWidth, height: 600, alignment: .top)
                    .background(BlurHashFullBleedBackground(.virtualBuddyBackground))
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
        .frame(width: VMConfigurationSheet.minWidth, height: 700)
        .padding()
        .background(Color.black.opacity(0.5))
        .overlay {
            content()
                .controlGroup()
        }
    }
}
#endif
