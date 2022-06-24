//
//  VMInstallationViewModel.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation
import UniformTypeIdentifiers
import Combine
import Virtualization
import VirtualCore

struct VMInstallData: Hashable {
    var name = "New Mac VM"
    var cookie: String?
    var restoreImageInfo: VBRestoreImageInfo? {
        didSet {
            if let url = restoreImageInfo?.url {
                restoreImageURL = url
            }
        }
    }
    var restoreImageURL: URL?
}

final class VMInstallationViewModel: ObservableObject {

    var library: VMLibraryController? {
        didSet {
            guard let library = library else {
                return
            }

            downloader = VBDownloader(with: library, cookie: data.cookie)
        }
    }

    private var downloader: VBDownloader?

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

    @Published var installMethod = InstallMethod.localFile

    @Published var data = VMInstallData() {
        didSet {
            if step == .restoreImageSelection {
                validateSelectedRestoreImage()
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

    @Published private(set) var buttonTitle = "Next"
    @Published private(set) var showNextButton = true
    @Published private(set) var disableNextButton = false

    private var needsDownload: Bool {
        guard let url = data.restoreImageURL else { return true }
        return !url.isFileURL
    }

    func goNext() {
        switch step {
            case .installKind:
                commitInstallMethod()
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
                showNextButton = true
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
                Task { await startInstallation() }

                showNextButton = false
            case .done:
                showNextButton = true
                disableNextButton = false
                buttonTitle = "Back to Library"

                cleanupInstallerArtifacts()
        }
    }

    private func commitInstallMethod() {
        switch installMethod {
        case .localFile:
            selectIPSWFile()
        case .remoteOptions:
            step = .restoreImageSelection
        case .remoteManual:
            step = .restoreImageInput
        }
    }

    private func loadRestoreImageOptions() {
        state = .loading(nil, nil)

        Task {
            do {
                let images = try await api.fetchRestoreImages()

                DispatchQueue.main.async {
                    self.restoreImageOptions = images

                    self.state = .idle
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func validateSelectedRestoreImage() {
        if let info = data.restoreImageInfo {
            if info.needsCookie, data.cookie == nil {
                disableNextButton = true
            } else {
                disableNextButton = false
            }
        } else {
            disableNextButton = data.restoreImageURL == nil
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
        if let info = data.restoreImageInfo {
            data.name = info.name
        } else {
            let inferredName = data.restoreImageURL?
                .deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "_Restore", with: "")
            guard let name = inferredName else { return }
            data.name = name
        }
    }

    private lazy var cancellables = Set<AnyCancellable>()

    @MainActor
    private func startDownload() {
        downloader!.cookie = data.cookie

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

    private var vmInstaller: VZMacOSInstaller?
    private var progressObservation: NSKeyValueObservation?

    @MainActor
    private func startInstallation() async {
        guard let library = library, let restoreURL = data.restoreImageURL else {
            state = .error("Missing library instance or restore image URL")
            return
        }

        do {
            state = .loading(nil, "Preparing Installation…\nThis may take a moment…")

            let vmURL = library.libraryURL
                .appendingPathComponent(data.name)
                .appendingPathExtension(VBVirtualMachine.bundleExtension)

            let model = try VBVirtualMachine(bundleURL: vmURL)

            let config = try await VMInstance.makeConfiguration(for: model, installImageURL: restoreURL)

            let vm = VZVirtualMachine(configuration: config)

            let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: restoreURL)
            vmInstaller = installer

            installer.install { [weak self] result in
                guard let self = self else { return }
                switch result {
                    case .failure(let error):
                        self.state = .error(error.localizedDescription)
                    case .success:
                        self.step = .done
                }
            }

            progressObservation = installer.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    let percent = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    self.state = .loading(percent, "Installing macOS…")
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func cleanup() {

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

    private func cleanupInstallerArtifacts() {
        progressObservation?.invalidate()
        progressObservation = nil

        vmInstaller = nil
    }

}

extension UTType {
    static let ipsw = UTType(filenameExtension: "ipsw")!
}
