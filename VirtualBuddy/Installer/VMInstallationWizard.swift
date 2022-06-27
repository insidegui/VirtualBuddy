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

            InstallMethodPicker(selection: $viewModel.installMethod)
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

            Picker("OS Version", selection: $viewModel.data.restoreImageInfo) {
                Text("Choose")
                    .tag(Optional<VBRestoreImageInfo>.none)

                ForEach(viewModel.restoreImageOptions) { option in
                    Text(option.name)
                        .tag(Optional<VBRestoreImageInfo>.some(option))
                }
            }

            if let selectedImage = viewModel.data.restoreImageInfo,
               let advisory = viewModel.restoreAdvisory(for: selectedImage)
            {
                avisoryView(with: advisory)
            }

            if let authRequirement = viewModel.data.restoreImageInfo?.authenticationRequirement {
                authenticationEntryPoint(with: authRequirement)
                    .padding(.top, 36)
            }

            if VBAPIClient.Environment.current != .production {
                Text("Notice: API environment override from defaults/arguments. Using API URL: \(VBAPIClient.Environment.current.baseURL)")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
    }

    @ViewBuilder
    private func avisoryView(with advisory: VMInstallationViewModel.RestoreImageAdvisory) -> some View {
        VStack {
            switch advisory {
            case .manualDownloadTip(let title, let url):
                Text("""
                     If you prefer to use a download manager, you may download \(title) from the following URL:

                     \(url)
                     """)
                .foregroundColor(.secondary)
            case .alreadyDownloaded(let title, let localURL):
                VStack {
                    Text("\(title) is already downloaded. Click \"Next\" below to re-download it or proceed with the installation right now by using the previously downloaded image.")
                        .foregroundColor(.green)

                    Button("Install Now") { viewModel.continueWithLocalFile(at: localURL) }
                        .controlSize(.large)
                }
            case .failure(let error):
                Text("VirtualBuddy couldn't create its downloads directory within \(library.libraryURL.path): \(error)")
                    .foregroundColor(.red)
            }
        }
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
        .padding(.top)
    }

    @State private var authRequirementFlow: VBRestoreImageInfo.AuthRequirement?

    @ViewBuilder
    private func authenticationEntryPoint(with requirement: VBRestoreImageInfo.AuthRequirement) -> some View {
        VStack(spacing: 16) {
            Text(requirement.explainer)
                .font(.system(size: 12))
                .lineSpacing(1.2)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                if viewModel.data.cookie == nil {
                    Button("Sign In…") {
                        authRequirementFlow = requirement
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)

                        Text("Authenticated")
                            .font(.system(size: 15, weight: .medium))
                    }

                    Button("Change Account…") {
                        authRequirementFlow = requirement
                    }
                }
            }
        }
        .controlSize(.large)
        .multilineTextAlignment(.center)
        .sheet(item: $authRequirementFlow, content: { requirement in
            AuthenticatingWebView(url: requirement.signInURL) { cookies in
                guard let headerValue = requirement.satisfiedCookieHeaderValue(with: cookies) else { return }
                self.viewModel.data.cookie = headerValue
                self.authRequirementFlow = nil
            }
            .frame(minWidth: 500, maxWidth: .infinity, minHeight: 550, maxHeight: .infinity)
        })
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
    }
}
