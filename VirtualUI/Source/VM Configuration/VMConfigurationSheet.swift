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
