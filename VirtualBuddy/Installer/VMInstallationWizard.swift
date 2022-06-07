//
//  VMInstallationWizard.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import VirtualCore

struct VMInstallationWizard: View {
    @EnvironmentObject var library: VMLibraryController
    @StateObject var viewModel = VMInstallationViewModel()

    @Environment(\.closeWindow) var closeWindow

    var body: some View {
        VStack {
            ZStack(alignment: .top) {
                switch viewModel.step {
                    case .installKind:
                        installKindSelection
                    case .restoreImageInput:
                        restoreImageURLInput
                    case .restoreImageSelection:
                        restoreImageSelection
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

    private var titleSpacing: CGFloat { 22 }

    @ViewBuilder
    private func title(_ str: String) -> some View {
        Text(str)
            .font(.system(.title, design: .rounded).weight(.medium))
            .padding(.vertical, titleSpacing)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var installKindSelection: some View {
        VStack {
            title("Select an installation method:")

            Group {
                Button("Download macOS", action: { viewModel.step = .restoreImageSelection })

                Button("Custom IPSW Download URL", action: { viewModel.step = .restoreImageInput })

                Button("Custom IPSW File", action: { viewModel.selectIPSWFile() })
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var restoreImageURLInput: some View {
        VStack {
            title("Enter the URL for the macOS IPSW:")

            TextField("URL", text: $viewModel.provisionalRestoreImageURL, onCommit: viewModel.goNext)
        }
    }

    @ViewBuilder
    private var restoreImageSelection: some View {
        VStack {
            title("Pick a macOS Version to Download and Install")

            Picker("OS Version", selection: $viewModel.data.restoreImageURL) {
                Text("Choose")
                    .tag(Optional<URL>.none)

                ForEach(viewModel.restoreImageOptions) { option in
                    Text(option.name)
                        .tag(Optional<URL>.some(option.url))
                }
            }
        }
    }

    @ViewBuilder
    private var renameVM: some View {
        VStack {
            title("Name Your Virtual Mac")

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
            title("Downloading \(vmDisplayName)")

            loadingView
        }
    }

    @ViewBuilder
    private var installProgress: some View {
        VStack {
            title("Installing \(vmDisplayName)")

            loadingView
        }
    }

    @ViewBuilder
    private var finishingLine: some View {
        VStack {
            title(vmDisplayName)

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
                            .font(.caption)
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
    }
}
