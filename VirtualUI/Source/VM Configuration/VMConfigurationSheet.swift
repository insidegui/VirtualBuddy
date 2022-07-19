//
//  VMConfigurationSheet.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

public struct VMConfigurationSheet: View {
    
    @StateObject private var viewModel: VMConfigurationViewModel
    
    /// The VM configuration as it existed when the user opened the configuration UI.
    /// Can be used to reset aspects of the configuration to their previous values.
    private var initialConfiguration: VBMacConfiguration
    
    /// The configuration that gets saved with the VM.
    /// Setting this saves the configuration.
    @Binding private var savedConfiguration: VBMacConfiguration
    
    private var machine: VBVirtualMachine
    
    @State private var showingValidationErrors = false
    
    /// Initializes the VM configuration sheet, bound to a VM configuration model.
    /// - Parameter machine:The VM being configured.
    /// - Parameter configuration: The binding that will be updated when the user saves the configuration by clicking the "Done" button.
    public init(machine: VBVirtualMachine, configuration: Binding<VBMacConfiguration>) {
        self.init(machine: machine, configuration: configuration, showingValidationErrors: false)
    }
    
    init(machine: VBVirtualMachine, configuration: Binding<VBMacConfiguration>, showingValidationErrors: Bool) {
        self.machine = machine
        self.initialConfiguration = configuration.wrappedValue
        self._savedConfiguration = configuration
        self._viewModel = .init(wrappedValue: VMConfigurationViewModel(config: configuration.wrappedValue, vm: machine))
        self._showingValidationErrors = .init(wrappedValue: showingValidationErrors)
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
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var buttons: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showingValidationErrors {
                validationErrors
            }
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Done") {
                    validateAndSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .disabled(showingValidationErrors)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Material.regular, in: Rectangle())
        .overlay(alignment: .top) { Divider() }
        .onChange(of: viewModel.config) { newValue in
            guard showingValidationErrors else { return }
            
            Task {
                if await newValue.validate(for: machine) == .supported {
                    showingValidationErrors = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var validationErrors: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.config.hostSupportState {
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
    
    private func validateAndSave() {
        showingValidationErrors = true
        
        Task {
            let state = await viewModel.updateSupportState()
            
            guard state.allowsSaving else { return }
            
            savedConfiguration = viewModel.config
            
            dismiss()
        }
    }
    
}
