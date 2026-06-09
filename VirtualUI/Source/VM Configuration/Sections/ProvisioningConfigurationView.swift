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

    private var provisioningBinding: Binding<VBMacProvisioningConfiguration> {
        Binding {
            configuration.provisioning ?? configuration.createProvisioningConfiguration()
        } set: { newValue in
            guard configuration.provisioningEnabled else { return }
            configuration.provisioning = newValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Create Mac User Account", isOn: $configuration.provisioningEnabled)

            ProvisioningForm(provisioning: provisioningBinding)
                .disabled(!configuration.provisioningEnabled)
                .opacity(configuration.provisioningEnabled ? 1 : 0.5)
        }
    }

    private struct ProvisioningForm: View {
        @Binding var provisioning: VBMacProvisioningConfiguration

        @Environment(\.isEnabled) private var isEnabled

        @State private var usernameEdited = false

        private enum Field {
            case fullName
            case username
            case password
            case passwordConfirmation
        }

        @FocusState private var focusedField: Field?

        @State private var passwordValue = ""
        @State private var passwordConfirmationValue = ""
        @State private var errors = [Field: String]()

        var body: some View {
            Form {
                validatedField("Full Name", text: $provisioning.fullName, field: .fullName, nextField: .username) {
                    $0.isEmpty ? "Full name can’t be empty." : nil
                }

                validatedField("Username", text: $provisioning.username, field: .username, nextField: .password) {
                    $0.isEmpty ? "Username can’t be empty." : nil
                }

                validatedField("Password", text: $passwordValue, field: .password, nextField: .passwordConfirmation, secure: true) {
                    if !$0.isEmpty {
                        if $0.count < 4 {
                            "Password must have 4 or more characters."
                        } else {
                            nil
                        }
                    } else {
                        nil
                    }
                }

                validatedField("Confirm Password", text: $passwordConfirmationValue, field: .passwordConfirmation, nextField: nil, secure: true) {
                    if !$0.isEmpty {
                        if $0 != passwordValue {
                            "Passwords don’t match."
                        } else {
                            nil
                        }
                    } else {
                        nil
                    }
                } commit: {
                    commit()
                }
            }
            .onChange(of: isEnabled) { oldValue, newValue in
                guard !oldValue, newValue else { return }
                focusedField = .fullName
            }
            .onChange(of: provisioning.username) { oldValue, newValue in
                guard focusedField == .username, newValue != oldValue else { return }
                usernameEdited = !newValue.isEmpty
            }
            .onChange(of: provisioning.fullName) { _, newValue in
                guard !usernameEdited, focusedField == .fullName else { return }
                provisioning.username = newValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
            }
        }

        @ViewBuilder
        private func validatedField(_ label: LocalizedStringKey, text: Binding<String>, field: Field, nextField: Field?, secure: Bool = false, validate: @escaping (_ value: String) -> String?, commit: (() -> ())? = nil) -> some View {
            if let error = errors[field] {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .minimumScaleFactor(0.7)
            }

            Group {
                if secure {
                    SecureField(label, text: text)
                } else {
                    TextField(label, text: text)
                }
            }
            .focused($focusedField, equals: field)
            .onSubmit {
                if let nextField {
                    focusedField = nextField
                } else {
                    if errors[field] == nil {
                        commit?()
                    }
                }
            }
            .onChange(of: focusedField) { oldValue, newValue in
                guard isEnabled, oldValue == field, newValue != field else { return }

                /// Ignore validation errors when unfocusing field if there are already errors for other fields.
                guard errors.keys.filter({ $0 != field }).isEmpty else { return }

                errors[field] = validate(text.wrappedValue)

                if errors[field] == nil {
                    commit?()
                }
            }
        }

        private func commit() {
            guard errors.isEmpty else { return }
            
            do {
                try provisioning.$password.write(passwordValue)

                focusedField = nil
            } catch {
                NSApp.presentError(error)
            }
        }
    }

}

private extension VBMacConfiguration {
    var provisioningEnabled: Bool {
        get { provisioning?.isEnabled ?? false }
        set {
            if newValue {
                if var provisioning {
                    provisioning.isEnabled = newValue
                    self.provisioning = provisioning
                } else {
                    self.provisioning = createProvisioningConfiguration()
                }
            } else {
                provisioning?.isEnabled = false
            }
        }
    }
}

#if DEBUG
#Preview {
    _ConfigurationSectionPreview { ProvisioningConfigurationView(configuration: $0) }
}
#endif
