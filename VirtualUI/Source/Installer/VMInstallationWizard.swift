//
//  VMInstallationWizard.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import VirtualCore
import Combine

public struct VMInstallationWizard: View {
    @EnvironmentObject var library: VMLibraryController
    @StateObject var viewModel: VMInstallationViewModel

    @Environment(\.closeWindow) var closeWindow

    public init(restoring restoreVM: VBVirtualMachine? = nil) {
        self._viewModel = .init(wrappedValue: VMInstallationViewModel(restoring: restoreVM))
    }

    private let stepValidationStateChanged = PassthroughSubject<Bool, Never>()

    public var body: some View {
        VStack {
            switch viewModel.step {
                case .systemType:
                    guestSystemTypeSelection
                case .installKind:
                    installKindSelection
                case .restoreImageInput:
                    restoreImageURLInput
                case .restoreImageSelection:
                    restoreImageSelection
                case .configuration:
                    configureVM
                case .name:
                    renameVM
                case .download:
                    downloadView
                case .install:
                    installProgress
                case .done:
                    finishingLine
            }

            if viewModel.showNextButton {
                Spacer()

                Button(viewModel.buttonTitle, action: {
                    if viewModel.step == .done {
                        library.loadMachines()
                        closeWindow()
                    } else {
                        viewModel.goNext()
                    }
                })
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.disableNextButton)
            }
        }
        .padding(viewModel.step != .configuration ? 16 : 0)
        .padding(.horizontal, viewModel.step != .configuration ? 36 : 0)
        .windowStyleMask([.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView])
        .windowTitleHidden(true)
        .windowTitleBarTransparent(true)
        .windowTitle("New Virtual Machine")
        .onReceive(stepValidationStateChanged) { isValid in
            viewModel.disableNextButton = !isValid
        }
        .edgesIgnoringSafeArea(.top)
        .frame(minWidth: 470)
    }

    @ViewBuilder
    private var guestSystemTypeSelection: some View {
        VStack {
            InstallationWizardTitle("Select an Operating System")

            GuestTypePicker(selection: $viewModel.selectedSystemType)
        }
        .frame(minWidth: 400, minHeight: 360)
    }

    @ViewBuilder
    private var installKindSelection: some View {
        VStack {
            InstallationWizardTitle("How Would You Like to Install \(viewModel.selectedSystemType.name)?")

            InstallMethodPicker(
                guestType: viewModel.selectedSystemType,
                selection: $viewModel.installMethod
            )
        }
    }

    @ViewBuilder
    private var restoreImageURLInput: some View {
        VStack {
            InstallationWizardTitle(viewModel.selectedSystemType.customURLPrompt)

            TextField("URL", text: $viewModel.provisionalRestoreImageURL, onCommit: viewModel.goNext)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private var restoreImageSelection: some View {
        VStack {
            InstallationWizardTitle(viewModel.selectedSystemType.restoreImagePickerPrompt)
            
            RestoreImagePicker(
                selection: $viewModel.data.restoreImageInfo,
                guestType: viewModel.selectedSystemType,
                validationChanged: stepValidationStateChanged,
                onUseLocalFile: { localURL in
                    viewModel.continueWithLocalFile(at: localURL)
                })
        }
    }
    
    @ViewBuilder
    private var configureVM: some View {
        VStack {
            InstallationWizardTitle("Configure Your Virtual Machine")

            if let machine = viewModel.machine {
                InstallConfigurationStepView(vm: machine) { configuredModel in
                    viewModel.machine = configuredModel
                    try? viewModel.machine?.saveMetadata()

                    viewModel.goNext()
                }
            } else {
                Text("Preparing…")
            }
        }
    }

    @ViewBuilder
    private var renameVM: some View {
        VStack {
            InstallationWizardTitle("Name Your Virtual Machine")

            VirtualMachineNameField(name: $viewModel.data.name, onCommit: viewModel.goNext)
        }
    }

    private var vmDisplayName: String {
        viewModel.data.name.isEmpty ? viewModel.selectedSystemType.name : viewModel.data.name
    }

    @ViewBuilder
    private var downloadView: some View {
        VStack {
            InstallationWizardTitle("Downloading \(vmDisplayName)")

            if let url = viewModel.data.downloadURL {
                RestoreImageDownloadView(imageURL: url, cookie: viewModel.data.cookie) { fileURL in
                    viewModel.handleDownloadCompleted(with: fileURL)
                }
            }
        }
    }

    @ViewBuilder
    private var installProgress: some View {
        VStack {
            InstallationWizardTitle("Installing \(vmDisplayName)")

            InstallProgressStepView()
                .environmentObject(viewModel)
        }
    }

    @ViewBuilder
    private var finishingLine: some View {
        VStack {
            InstallationWizardTitle(vmDisplayName)

            Text(viewModel.selectedSystemType.installFinishedMessage)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        switch viewModel.state {
            case .loading(let progress, let info):
                VStack {
                    ProgressView(value: progress) { }
                        .progressViewStyle(.linear)
                        .labelsHidden()

                    if let info = info {
                        Text(info)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            case .error(let message):
                Text(message)
            case .idle:
                Text("Starting…")
                    .foregroundColor(.secondary)
        }
    }

}

struct VMInstallationWizard_Previews: PreviewProvider {
    static var previews: some View {
        VMInstallationWizard()
            .environmentObject(VMLibraryController.shared)
    }
}
