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
    @ObservedObject var library: VMLibraryController
    @StateObject var viewModel: VMInstallationViewModel

    @Environment(\.closeWindow) var closeWindow

    public init(library: VMLibraryController, restoringAt restoreURL: URL? = nil) {
        self._library = .init(initialValue: library)
        self._viewModel = .init(wrappedValue: VMInstallationViewModel(library: library, restoringAt: restoreURL))
    }

    private let stepValidationStateChanged = PassthroughSubject<Bool, Never>()

    public var body: some View {
        NavigationStack {
            VStack {
                switch viewModel.step {
                    case .systemType:
                        guestSystemTypeSelection
                            .navigationSubtitle(Text("Choose Operating System"))
                    case .installKind:
                        installKindSelection
                    case .restoreImageInput:
                        restoreImageURLInput
                    case .restoreImageSelection:
                        restoreImageSelection
                            .navigationSubtitle(Text(viewModel.selectedSystemType.restoreImagePickerPrompt))
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
                }
            }
            .padding()
            .onReceive(stepValidationStateChanged) { isValid in
                viewModel.disableNextButton = !isValid
            }
            .navigationTitle(Text("Virtual Machine Setup"))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .toolbar {
            Text("").hidden()
        }
    }
    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Spacer()

            nextButton
        }
        .padding()
        .background(Material.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var nextButton: some View {
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

    @ViewBuilder
    private var guestSystemTypeSelection: some View {
        GuestTypePicker(selection: $viewModel.selectedSystemType)
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
        RestoreImagePicker(
            library: library,
            selection: $viewModel.data.resolvedRestoreImage,
            guestType: viewModel.selectedSystemType,
            validationChanged: stepValidationStateChanged,
            onUseLocalFile: { localURL in
                viewModel.continueWithLocalFile(at: localURL)
            })
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

            VirtualMachineNameField(name: $viewModel.data.name)
        }
    }

    private var vmDisplayName: String {
        viewModel.data.name.isEmpty ? viewModel.selectedSystemType.name : viewModel.data.name
    }

    @ViewBuilder
    private var downloadView: some View {
        VStack {
            InstallationWizardTitle("Downloading \(vmDisplayName)")

            if let downloader = viewModel.downloader {
                RestoreImageDownloadView(downloader: downloader)
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

#if DEBUG
#Preview {
    VMInstallationWizard(library: .preview)
}
#endif
