//
//  ProvisioningConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 09/06/26.
//

import SwiftUI
import VirtualCore

struct ProvisioningConfigurationView: View {
    
    @Binding var configuration: VBMacConfiguration
    var contextForbidden = false
    @State private var isShowingProvisioningFormSheet = false

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    private var feature: ResolvedVirtualizationFeature? { resolvedRestoreImage?.feature(id: CatalogFeatureID.provisioning) }

    private var unsupported: Bool { feature?.status.isUnsupported == true }

    private var logsInAutomatically: Binding<Bool> {
        Binding {
            configuration.provisioning?.logsInAutomatically ?? false
        } set: { newValue in
            configuration.provisioning?.logsInAutomatically = newValue
        }
    }

    private var enablesRemoteLogin: Binding<Bool> {
        Binding {
            configuration.provisioning?.enablesRemoteLogin ?? false
        } set: { newValue in
            configuration.provisioning?.enablesRemoteLogin = newValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Automatically create a macOS account on first boot", isOn: $configuration.provisioningEnabled)

                Spacer()

                Button {
                    isShowingProvisioningFormSheet = true
                } label: {
                    Text(configuration.provisioningSetup ? "Account Details…" : "Set Up Account…")
                }
                .controlSize(.small)
                .disabled(!configuration.provisioningEnabled)
                .modifier(AttentionBounceViewModifier(enabled: configuration.provisioningEnabled && !configuration.provisioningSetup))
            }

            Group {
                Toggle("Log in automatically", isOn: logsInAutomatically)
                    .help(configuration.provisioningSetup ? "Automatically log in using this account, bypassing the macOS Lock Screen" : "")

                Toggle("Enable remote login (SSH)", isOn: enablesRemoteLogin)
                    .help(configuration.provisioningSetup ? "Allow logging in with this account using SSH" : "")
            }
            .disabled(!configuration.provisioningSetup)
            .help(!configuration.provisioningSetup ? "Please set up account first" : "")

            if unsupported, let feature, let message = feature.status.supportMessage {
                Text(verbatim: message)
                    // HACK: Force yellow warning when host supports provisioning, red only when host doesn't support provisioning
                    .foregroundStyle(VBMacConfiguration.hostSupportsProvisioning ? .yellow : .red)
            }
        }
        .sheet(isPresented: $isShowingProvisioningFormSheet) {
            NavigationStack {
                ProvisioningForm(configuration: $configuration)
                    .navigationTitle(Text("Mac User Account"))
            }
        }
        .onChange(of: configuration.provisioningEnabled) { oldValue, newValue in
            /// Automatically present form sheet when provisioning is enabled unless it's already set up.
            guard !configuration.provisioningSetup else { return }
            guard !oldValue, newValue else { return }
            guard !ProcessInfo.isSwiftUIPreview else {
                UILog("I would present the provisioning form sheet now, but I'm in a preview")
                return
            }

            isShowingProvisioningFormSheet = true
        }
        .opacity(contextForbidden ? 0 : 1)
        .disabled(contextForbidden || unsupported)
        .overlay {
            if contextForbidden {
                Text("Available only before the virtual machine is started for the first time.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    fileprivate struct ProvisioningForm: View {
        typealias FormData = VBMacProvisioningConfiguration.FormData
        typealias Field = VBMacProvisioningConfiguration.FormField

        @Binding var configuration: VBMacConfiguration
        @State private var data = FormData()

        @Environment(\.isEnabled) private var isEnabled

        @State private var usernameEdited = false

        @FocusState private var focusedField: Field?

        @Environment(\.dismiss) private var dismiss

        @State private var errors = [Field: String]()

        var body: some View {
            Form {
                validatedField("Full Name", text: $data.fullName, field: .fullName, nextField: .username)

                validatedField("Username", text: $data.username, field: .username, nextField: .password)

                validatedField("Password", text: $data.password, field: .password, nextField: .passwordConfirmation, secure: true)

                validatedField("Confirm Password", text: $data.passwordConfirmation, field: .passwordConfirmation, nextField: nil, secure: true) {
                    save(dismiss: true)
                }
            }
            #if DEBUG
            .task {
                guard ProcessInfo.isSwiftUIPreview else { return }
                errors[.username] = data.validationErrorMessage(for: .username, value: "")
            }
            #endif
            .formStyle(.grouped)
            .onChange(of: isEnabled) { oldValue, newValue in
                guard !oldValue, newValue else { return }
                focusedField = .fullName
            }
            .onChange(of: data.username) { oldValue, newValue in
                guard focusedField == .username, newValue != oldValue else { return }
                usernameEdited = !newValue.isEmpty
            }
            .onChange(of: data.fullName) { _, newValue in
                guard !usernameEdited, focusedField == .fullName else { return }
                data.username = newValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
            }
            .toolbar {
                ToolbarItemGroup(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                    }
                }

                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        save(dismiss: true)
                    } label: {
                        Text("Save")
                    }
                }
            }
            /// Recover existing provisioning configuration if available.
            .task {
                guard let provisioning = configuration.provisioning else { return }
                data = FormData(provisioning)
            }
        }

        @ViewBuilder
        private func validatedField(_ label: LocalizedStringKey, text: Binding<String>, field: Field, nextField: Field?, secure: Bool = false, onSubmit: (() -> ())? = nil) -> some View {
            LabeledContent {
                Group {
                    if secure {
                        SecureField(label, text: text)
                    } else {
                        TextField(label, text: text)
                    }
                }
                .labelsHidden()
                .opacity(errors[field] != nil ? 0.1 : 1.0)
                .overlay(alignment: .trailing) {
                    ZStack {
                        if let error = errors[field] {
                            Text(error)
                                .foregroundStyle(.red)
                                .fontWeight(.medium)
                                .minimumScaleFactor(0.7)
                                .monospacedDigit()
                                .contentShape(.rect)
                                .highPriorityGesture(TapGesture().onEnded({
                                    errors[field] = nil
                                    focusedField = field
                                }))
                                .transition(.blurReplace)
                        }
                    }
                    /// Hide error when field is focused so that user can see what they're typing.
                    .onChange(of: focusedField) { oldValue, newValue in
                        guard errors[field] != nil, oldValue != field, newValue == field else { return }
                        errors[field] = nil
                    }
                    /// Reset errors when editing value so that user can see what they're typing even before validation changes.
                    .onChange(of: text.wrappedValue) {
                        guard errors[field] != nil, focusedField == field else { return }
                        errors[field] = nil
                    }
                    .animation(.default, value: errors[field] != nil)
                }
            } label: {
                Text(label)
            }
            .focused($focusedField, equals: field)
            .onSubmit {
                if let nextField {
                    focusedField = nextField
                } else {
                    errors[field] = data.validationErrorMessage(for: field, value: text.wrappedValue)

                    if errors[field] == nil {
                        onSubmit?()
                    }
                }
            }
            .onChange(of: focusedField) { oldValue, newValue in
                guard isEnabled, oldValue == field, newValue != field else { return }

                /// Ignore validation errors when unfocusing field if there are already errors for other fields.
                guard errors.keys.filter({ $0 != field }).isEmpty else { return }

                errors[field] = data.validationErrorMessage(for: field, value: text.wrappedValue)
            }
            .onChange(of: text.wrappedValue) { _, newValue in
                guard errors[field] != nil else { return }
                errors[field] = data.validationErrorMessage(for: field, value: text.wrappedValue)
            }
        }

        private func save(dismiss: Bool = false) {
            guard errors.isEmpty else { return }
            
            do {
                try configuration.applyProvisioningConfiguration(with: data)

                guard !dismiss else {
                    self.dismiss()
                    return
                }

                focusedField = nil
            } catch let error as VBMacConfiguration.ProvisioningSetupError {
                errors = error.validationErrorMessages
            } catch {
                NSApp.presentError(error)
            }
        }
    }

}

struct AttentionBounceViewModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .phaseAnimator([0, 1, 2], trigger: enabled) { content, phase in
                content
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange)
                            .opacity(enabled ? (phase == 1 ? 0.7 : 0.0) : 0.0)
                            .visualEffect { content, _ in
                                content.blur(radius: 2)
                            }
                            .blendMode(.overlay)
                    }
                    .visualEffect { [enabled] content, _ in
                        content
                            .scaleEffect(enabled ? (phase == 1 ? 1.1 : 1.0) : 1.0)
                    }
            } animation: { phase in
                if enabled {
                    Animation.smooth(duration: phase == 1 ? 0.5 : 0.3, extraBounce: 0)
                } else {
                    Animation.linear(duration: 0)
                }
            }
    }
}

#if DEBUG
#Preview("Section") {
    _ConfigurationSectionPreview { ProvisioningConfigurationView(configuration: $0) }
}

#Preview("Account Sheet") {
    @Previewable @State var config: VBMacConfiguration = .preview

    ProvisioningConfigurationView.ProvisioningForm(configuration: $config)
}
#endif
