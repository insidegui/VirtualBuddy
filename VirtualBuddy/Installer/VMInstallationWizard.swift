//
//  VMInstallationWizard.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import VirtualCore

struct VMInstallData: Hashable {
    var restoreImageURL: URL?
}

final class VMInstallationViewModel: ObservableObject {

    enum Step: Hashable {
        case installKind
        case restoreImageInput
        case restoreImageSelection
        case download
        case install
        case done
    }

    enum State: Hashable {
        case idle
        case loading(_ progress: Double?)
        case error(_ message: String)
    }

    @Published var data = VMInstallData() {
        didSet {
            if step == .restoreImageSelection {
                disableNextButton = data.restoreImageURL == nil
            }
        }
    }

    @Published private(set) var state = State.idle

    let api = VBAPIClient()

    @Published var step = Step.installKind {
        didSet {
            guard step != oldValue else { return }

            performActions(for: step)
        }
    }

    @Published
    private(set) var restoreImageOptions = [VBRestoreImageInfo]()

    @Published private(set) var showNextButton = false
    @Published private(set) var disableNextButton = false

    func goNext() {
        switch step {
            case .installKind:
                break
            case .restoreImageInput:
                step = .download
            case .restoreImageSelection:
                step = .download
            case .download:
                step = .install
            case .install:
                step = .done
            case .done:
                break
        }
    }

    private func performActions(for step: Step) {
        switch step {
            case .installKind:
                showNextButton = false
            case .restoreImageInput:
                showNextButton = true
            case .restoreImageSelection:
                loadRestoreImageOptions()

                showNextButton = true
                disableNextButton = true
            case .download:
                commitOSSelection()

                startInstallation()

                showNextButton = false
            case .install:
                showNextButton = false
            case .done:
                break
        }
    }

    private func loadRestoreImageOptions() {
        state = .loading(nil)

        Task {
            do {
                let images = try await api.fetchRestoreImages()

                restoreImageOptions = images

                state = .idle
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    private func commitOSSelection() {
        if !provisionalRestoreImageURL.isEmpty {
            guard let url = URL(string: provisionalRestoreImageURL) else {
                state = .error("Invalid URL: \(provisionalRestoreImageURL)")
                return
            }

            self.data.restoreImageURL = url
        }
    }

    private func startInstallation() {

    }

    @Published var provisionalRestoreImageURL = "" {
        didSet {
            if step == .restoreImageInput {
                disableNextButton = !provisionalRestoreImageURL.hasPrefix("https")
                || !provisionalRestoreImageURL.hasSuffix("ipsw")
            }
        }
    }

}

struct VMInstallationWizard: View {
    @EnvironmentObject var library: VMLibraryController
    @StateObject var viewModel = VMInstallationViewModel()

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
                    case .download:
                        Text("download")
                    case .install:
                        Text("install")
                    case .done:
                        Text("done")
                }
            }

            Spacer()

            if viewModel.showNextButton {
                Button("Next", action: viewModel.goNext)
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
                Button("Select an OS", action: { viewModel.step = .restoreImageSelection })

                Button("Enter Restore Image URL", action: { viewModel.step = .restoreImageInput })
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var restoreImageURLInput: some View {
        VStack {
            title("Enter the URL for the macOS IPSW:")

            TextField("URL", text: $viewModel.provisionalRestoreImageURL)
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

}

struct VMInstallationWizard_Previews: PreviewProvider {
    static var previews: some View {
        VMInstallationWizard()
    }
}
