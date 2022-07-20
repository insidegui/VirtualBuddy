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
    
    private var showsCancelButton = true
    private var customConfirmationButtonAction: (() -> Void)? = nil
    
    /// Initializes the VM configuration sheet, bound to a VM configuration model.
    /// - Parameter configuration: The binding that will be updated when the user saves the configuration by clicking the "Done" button.
    public init(configuration: Binding<VBMacConfiguration>) {
        self.init(configuration: configuration, showingValidationErrors: false)
    }
    
    init(configuration: Binding<VBMacConfiguration>, showingValidationErrors: Bool = false, showsCancelButton: Bool = true, customConfirmationButtonAction: (() -> Void)? = nil) {
        self.initialConfiguration = configuration.wrappedValue
        self._savedConfiguration = configuration
        self._showingValidationErrors = .init(wrappedValue: showingValidationErrors)
        self.showsCancelButton = showsCancelButton
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
                
                Button("Done") {
                    validateAndSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(showingValidationErrors)
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
                customConfirmationButtonAction()
            } else {
                dismiss()
            }
        }
    }
    
}
