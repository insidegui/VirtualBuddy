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
    @StateObject var viewModel = VMInstallationViewModel()

    @Environment(\.closeWindow) var closeWindow
    
    public init() { }
    
    private let stepValidationStateChanged = PassthroughSubject<Bool, Never>()

    public var body: some View {
        VStack {
            ZStack(alignment: .top) {
                switch viewModel.step {
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
            }

            Spacer()

            if viewModel.showNextButton {
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
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .top)
        .windowStyleMask([.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView])
        .windowTitle("New macOS VM")
        .onReceive(stepValidationStateChanged) { isValid in
            viewModel.disableNextButton = !isValid
        }
    }

    @ViewBuilder
    private var installKindSelection: some View {
        VStack {
            InstallationWizardTitle("Select an installation method:")

            InstallMethodPicker(selection: $viewModel.installMethod)
        }
    }

    @ViewBuilder
    private var restoreImageURLInput: some View {
        VStack {
            InstallationWizardTitle("Enter the URL for the macOS IPSW:")

            TextField("URL", text: $viewModel.provisionalRestoreImageURL, onCommit: viewModel.goNext)
        }
    }

    @ViewBuilder
    private var restoreImageSelection: some View {
        VStack {
            InstallationWizardTitle("Pick a macOS Version to Download and Install")
            
            RestoreImagePicker(
                selection: $viewModel.data.restoreImageInfo,
                validationChanged: stepValidationStateChanged,
                onUseLocalFile: { localURL in
                    viewModel.continueWithLocalFile(at: localURL)
                })
        }
    }
    
    @ViewBuilder
    private var configureVM: some View {
        VStack {
            InstallationWizardTitle("Configure Your Virtual Mac")

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
            InstallationWizardTitle("Name Your Virtual Mac")

            HStack {
                TextField("VM Name", text: $viewModel.data.name, onCommit: viewModel.goNext)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)

                Spacer()

                Button {
                    viewModel.data.name = RandomNameGenerator.shared.newName()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .help("Generate new name")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 15, weight: .medium, design: .rounded))
            }
        }
    }

    private var vmDisplayName: String {
        viewModel.data.name.isEmpty ?
        viewModel.data.restoreImageURL?.lastPathComponent ?? "-"
        : viewModel.data.name
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

            Text("Your VM is ready!")
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
