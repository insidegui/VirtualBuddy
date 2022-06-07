//
//  VMInstallationWizard.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import VirtualCore
import UniformTypeIdentifiers
import Combine

struct VMInstallData: Hashable {
    var name = "New Mac VM"
    var restoreImageURL: URL?
}

final class VMInstallationViewModel: ObservableObject {

    var downloader: VBDownloader?

    enum Step: Hashable {
        case installKind
        case restoreImageInput
        case restoreImageSelection
        case name
        case download
        case install
        case done
    }

    enum State: Hashable {
        case idle
        case loading(_ progress: Double?, _ info: String?)
        case error(_ message: String)
    }

    @Published var data = VMInstallData() {
        didSet {
            if step == .restoreImageSelection {
                disableNextButton = data.restoreImageURL == nil
            }
            if step == .name {
                disableNextButton = data.name.isEmpty
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

    private var needsDownload: Bool {
        guard let url = data.restoreImageURL else { return true }
        return !url.isFileURL
    }

    func goNext() {
        switch step {
            case .installKind:
                break
            case .restoreImageInput, .restoreImageSelection:
                step = .name
            case .name:
                step = needsDownload ? .download : .install
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
            case .name:
                showNextButton = true

                commitOSSelection()

                createInitialName()
            case .download:
                Task { await startDownload() }

                showNextButton = false
            case .install:
                startInstallation()

                showNextButton = false
            case .done:
                break
        }
    }

    private func loadRestoreImageOptions() {
        state = .loading(nil, nil)

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

    private func createInitialName() {
        let inferredName = data.restoreImageURL?
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_Restore", with: "")
        guard let name = inferredName else { return }
        data.name = name
    }

    private lazy var cancellables = Set<AnyCancellable>()

    @MainActor
    private func startDownload() {
        downloader!.$state.sink { [weak self] downloadState in
            guard let self = self else { return }
            self.handleDownloadState(downloadState)
        }
        .store(in: &cancellables)

        downloader!.startDownload(with: data.restoreImageURL!)
    }

    private func handleDownloadState(_ downloadState: VBDownloader.State) {
        guard step == .download else { return }

        switch downloadState {
            case .idle:
                break
            case .downloading(let progress, let eta):
                let info: String?
                if let eta = eta {
                    info = "Estimated time remaining: \(formattedETA(from: eta))"
                } else {
                    info = nil
                }

                self.state = .loading(progress, info)
            case .failed(let error):
                self.state = .error("Download failed: \(error)")
            case .done:
                goNext()
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

    func selectIPSWFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.ipsw]
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        data.restoreImageURL = url

        step = .name
    }

    private func formattedETA(from eta: Double) -> String {
        let time = Int(eta)

        let seconds = time % 60
        let minutes = (time / 60) % 60
        let hours = (time / 3600)

        if hours >= 1 {
            return String(format: "%0.2d:%0.2d:%0.2d",hours,minutes,seconds)
        } else {
            return String(format: "%0.2d:%0.2d",minutes,seconds)
        }

    }

}

extension UTType {
    static let ipsw = UTType(filenameExtension: "ipsw")!
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
                    case .name:
                        renameVM
                    case .download:
                        downloadProgress
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
        .onAppear {
            guard viewModel.downloader == nil else { return }
            viewModel.downloader = VBDownloader(with: library)
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

    @ViewBuilder
    private var downloadProgress: some View {
        VStack {
            title("Downloading \(viewModel.data.restoreImageURL?.lastPathComponent ?? "-")")

            switch viewModel.state {
                case .loading(let progress, let info):
                    VStack {
                        ProgressView("Downloading", value: progress)
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

}

struct VMInstallationWizard_Previews: PreviewProvider {
    static var previews: some View {
        VMInstallationWizard()
    }
}
