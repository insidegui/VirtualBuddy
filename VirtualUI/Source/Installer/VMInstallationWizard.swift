//
//  VMInstallationWizard.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import VirtualCore

public struct VMInstallationWizard: View {
    @EnvironmentObject var library: VMLibraryController
    @StateObject var viewModel = VMInstallationViewModel()

    @Environment(\.closeWindow) var closeWindow
    
    public init() { }

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
                    case .configure:
                        configureVM
                    case .name:
                        renameVM
                    case .download:
                        downloadProgress
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
        .padding()
        .padding(.horizontal, 36)
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .top)
        .windowStyleMask([.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView])
        .windowTitle("New macOS VM")
        .onAppear {
            guard viewModel.library == nil else { return }
            viewModel.library = library
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

            RestoreImagePicker(selection: $viewModel.data.restoreImageInfo, onUseLocalFile: { localURL in
                viewModel.continueWithLocalFile(at: localURL)
            })
        }
    }
    
    @ViewBuilder
    private var configureVM: some View {
        VStack {
            InstallationWizardTitle("Configure Your Virtual Mac")

            
        }
    }

    @ViewBuilder
    private var renameVM: some View {
        VStack {
            InstallationWizardTitle("Name Your Virtual Mac")

            TextField("VM Name", text: $viewModel.data.name, onCommit: viewModel.goNext)
        }
    }

    private var vmDisplayName: String {
        viewModel.data.name.isEmpty ?
        viewModel.data.restoreImageURL?.lastPathComponent ?? "-"
        : viewModel.data.name
    }

    @ViewBuilder
    private var downloadProgress: some View {
        VStack {
            InstallationWizardTitle("Downloading \(vmDisplayName)")

            loadingView
        }
    }

    @ViewBuilder
    private var installProgress: some View {
        VStack {
            InstallationWizardTitle("Installing \(vmDisplayName)")

            loadingView
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
