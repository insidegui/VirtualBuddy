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

    @Binding private var savedMetadata: VBVirtualMachine.Metadata
    private var appliesMetadataChanges: Bool

    @State private var showValidationErrors = false
    @State private var showResizeConfirmation = false
    @State private var showFileVaultError = false
    @State private var fileVaultErrorMessage = ""
    @State private var isPreparingDiskResize = false
    
    private var showsCancelButton: Bool { viewModel.context == .postInstall }
    private var customConfirmationButtonAction: ((VBMacConfiguration) -> Void)? = nil

    private let diskResizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.formattingContext = .standalone
        formatter.countStyle = .binary
        return formatter
    }()
    
    /// Initializes the VM configuration sheet, bound to a VM configuration model.
    /// - Parameter configuration: The binding that will be updated when the user saves the configuration by clicking the "Done" button.
    public init(configuration: Binding<VBMacConfiguration>, metadata: Binding<VBVirtualMachine.Metadata>? = nil) {
        self.init(configuration: configuration, metadata: metadata, showingValidationErrors: false)
    }
    
    init(
        configuration: Binding<VBMacConfiguration>,
        metadata: Binding<VBVirtualMachine.Metadata>? = nil,
        showingValidationErrors: Bool = false,
        customConfirmationButtonAction: ((VBMacConfiguration) -> Void)? = nil
    ) {
        self.initialConfiguration = configuration.wrappedValue
        self._savedConfiguration = configuration
        self._savedMetadata = metadata ?? .constant(VBVirtualMachine.Metadata())
        self.appliesMetadataChanges = metadata != nil
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
        .virtualBuddyBottomBar { buttons }
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
                .disabled(showValidationErrors || isPreparingDiskResize)
            }
        }
        .onChange(of: viewModel.config) { _, newValue in
            guard showValidationErrors else { return }
            
            Task {
                if await viewModel.validate() == .supported {
                    showValidationErrors = false
                }
            }
        }
        .alert("Resize Disk Image", isPresented: $showResizeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Resize") {
                confirmDiskResizeAndSave()
            }
        } message: {
            Text(viewModel.diskImageResizeConfirmationMessage(formatter: diskResizeFormatter))
        }
        .alert("FileVault Enabled", isPresented: $showFileVaultError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(fileVaultErrorMessage)
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

            if viewModel.hasPendingDiskImageResizeConfirmations {
                await MainActor.run {
                    showValidationErrors = false
                    showResizeConfirmation = true
                }
                return
            }

            await MainActor.run {
                showValidationErrors = false
                saveConfiguration()
            }
        }
    }

    private func confirmDiskResizeAndSave() {
        isPreparingDiskResize = true

        Task {
            if let deviceName = await viewModel.firstFileVaultProtectedPendingResizeName() {
                await MainActor.run {
                    fileVaultErrorMessage = "The \(deviceName) disk has FileVault encryption enabled. To resize the disk, you must first disable FileVault in the guest operating system's System Settings, then restart the virtual machine before attempting to resize again."
                    showFileVaultError = true
                    isPreparingDiskResize = false
                }
                return
            }

            await MainActor.run {
                viewModel.confirmPendingDiskImageResizes()
                isPreparingDiskResize = false
                saveConfiguration()
            }
        }
    }

    private func saveConfiguration() {
        savedConfiguration = viewModel.config

        if appliesMetadataChanges {
            var metadata = savedMetadata
            viewModel.applyPendingDiskImageResizeIDs(to: &metadata)
            savedMetadata = metadata
        }

        if let customConfirmationButtonAction {
            customConfirmationButtonAction(savedConfiguration)
        } else {
            dismiss()
        }
    }
    
}

#if DEBUG
struct VMConfigurationSheet_Previews: PreviewProvider {
    static var height: Double { 1200 }

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
                        .frame(width: VMConfigurationSheet.minWidth, height: VMConfigurationSheet_Previews.height, alignment: .top)
                }
            } else {
                VMConfigurationSheet(configuration: $vm.configuration)
                    .environmentObject(VMConfigurationViewModel(vm, context: context))
                    .frame(width: VMConfigurationSheet.minWidth, height: VMConfigurationSheet_Previews.height, alignment: .top)
                    .background(BlurHashFullBleedBackground(blurHash: .virtualBuddyBackground))
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
        .frame(width: VMConfigurationSheet.minWidth, height: VMConfigurationSheet_Previews.height)
        .padding()
        .background(Color.black.opacity(0.5))
        .overlay {
            content()
                .controlGroup()
        }
    }
}
#endif
