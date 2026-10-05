//
//  VMSessionConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore

struct VMSessionConfigurationView: View {
    @EnvironmentObject var controller: VMController

    @State private var isShowingVMSettings = false

    private var vm: VBVirtualMachine { controller.virtualMachineModel }

    private var resolvedRestoreImage: ResolvedRestoreImage? {
        let catalog = SoftwareCatalog.current(for: vm.configuration.systemType)

        if let remoteURL = vm.metadata.remoteInstallImageURL,
           let resolved = catalog.resolvedRestoreImage(matching: remoteURL, guestType: vm.configuration.systemType) {
            return resolved
        }

        if let localURL = vm.metadata.installImageURL,
           let resolved = catalog.resolvedRestoreImage(matching: localURL, guestType: vm.configuration.systemType) {
            return resolved
        }

        return nil
    }

    var body: some View {
        SelfSizingGroupedForm(minHeight: 100) {
            if let savedSession = controller.savedSession {
                SavedSessionDetailsSection(descriptor: savedSession)
            } else if let issue = saveEligibilityIssue {
                Label {
                    Text("Save & Close isn’t available. \(issue.explanation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                }
            }

            /// The boot mode of a saved session can't change. Discarding the session is the way to boot differently.
            Group {
                if showInstallDeviceOption {
                    Toggle("Boot on install drive", isOn: $controller.options.bootOnInstallDevice)
                }

                if showRecoveryModeOption {
                    Toggle("Boot in recovery mode", isOn: $controller.options.bootInRecoveryMode)
                        .disabled(controller.options.bootInDFUMode)
                }

                if showDFUOption {
                    Toggle("Boot in DFU mode", isOn: $controller.options.bootInDFUMode)
                        .disabled(controller.options.bootInRecoveryMode)
                }
            }
            .disabled(controller.savedSession != nil)

            Toggle("Capture system keyboard shortcuts", isOn: $controller.virtualMachineModel.configuration.captureSystemKeys)

            Button("Virtual Machine Settings…") {
                isShowingVMSettings.toggle()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(-12)
        .clipShape(shape)
        .airMaterialBackground(visualEffect: .hudWindow, glassEffect: .clear, in: shape)
        .sheet(isPresented: $isShowingVMSettings) {
            VMConfigurationSheet(
                configuration: $controller.virtualMachineModel.configuration
            )
            .environmentObject(makeConfigurationViewModel())
        }
    }

    private func makeConfigurationViewModel() -> VMConfigurationViewModel {
        let viewModel = VMConfigurationViewModel(vm, resolvedRestoreImage: resolvedRestoreImage)
        viewModel.discardSavedSessionHandler = { [weak controller] in try await controller?.discardSavedSession() }
        return viewModel
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18)
    }

    private var showInstallDeviceOption: Bool { vm.configuration.systemType == .linux && vm.metadata.installImageURL != nil }

    private var showRecoveryModeOption: Bool { vm.configuration.systemType == .mac }

    private var showDFUOption: Bool { VBMacConfiguration.appBuildAllowsDFUMode && vm.configuration.systemType == .mac }

    /// Why saving the session isn't available for this virtual machine, shown before the user depends on it.
    private var saveEligibilityIssue: SavedSessionEligibility.Issue? {
        guard controller.saveEligibility.isApplicable else { return nil }
        return controller.saveEligibility.primaryIssue
    }
}

#if DEBUG
#Preview("Glass") {
    VirtualMachineSessionViewPreview()
}

#Preview("No Glass") {
    VirtualMachineSessionViewPreview()
        .environment(\.preview_overrideLiquidGlassSupported, false)
}
#endif
