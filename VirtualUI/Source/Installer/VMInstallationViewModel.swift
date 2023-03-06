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
    var name = RandomNameGenerator.shared.newName()
    var cookie: String?
    var restoreImageInfo: VBRestoreImageInfo? {
        didSet {
            if let url = restoreImageInfo?.url {
                restoreImageURL = url
            }
        }
    }
    var restoreImageURL: URL?
    var installImageURL: URL?
    
    var downloadURL: URL? {
        restoreImageURL ?? restoreImageInfo?.url
    }
}

final class VMInstallationViewModel: ObservableObject {
    
    enum Step: Int, Hashable {
        case systemType
        case installKind
        case restoreImageInput
        case restoreImageSelection
        case name
        case configuration
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

    @Published var selectedSystemType: VBGuestType = .mac
    
    @Published var machine: VBVirtualMachine?

    @Published var data = VMInstallData() {
        didSet {
            if step == .name {
                disableNextButton = data.name.isEmpty
            }
        }
    }

    @Published private(set) var state = State.idle

    @Published var step = Step.systemType {
        didSet {
            guard step != oldValue else { return }

            performActions(for: step)
        }
    }

    @Published
    private(set) var restoreImageOptions = [VBRestoreImageInfo]()

    @Published private(set) var buttonTitle = "Continue"
    @Published private(set) var showNextButton = true
    @Published  var disableNextButton = false

    init() {
        /// Skip OS selection if there's only a single supported OS.
        step = VBGuestType.supportedByHost.count > 1 ? .systemType : .installKind
    }

    private var needsDownload: Bool {
        guard let url = data.restoreImageURL ?? data.installImageURL else { return true }
        return !url.isFileURL
    }

    func goNext() {
        switch step {
            case .systemType:
                step = .installKind
            case .installKind:
                commitInstallMethod()
            case .restoreImageInput, .restoreImageSelection:
                step = .name
            case .name:
                step = .configuration
            case .configuration:
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
            case .systemType, .installKind:
                showNextButton = true
            case .restoreImageInput:
                showNextButton = true
                validateCustomURL()
            case .restoreImageSelection:
                showNextButton = true
                disableNextButton = true
            case .name:
                commitOSSelection()
            
                showNextButton = true
            case .configuration:
                showNextButton = false
                disableNextButton = true
            
                Task {
                    do {
                        try await prepareModel()
                    } catch {
                        state = .error("Failed to prepare VM model: \(error.localizedDescription)")
                    }
                }
            case .download:
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
            selectInstallFile()
        case .remoteOptions:
            step = .restoreImageSelection
        case .remoteManual:
            step = .restoreImageInput
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

    func handleDownloadCompleted(with fileURL: URL) {
        data.restoreImageURL = fileURL
        goNext()
    }

    private lazy var cancellables = Set<AnyCancellable>()

    private var vmInstaller: VZMacOSInstaller?
    private var progressObservation: NSKeyValueObservation?
    
    @MainActor
    private func prepareModel() throws {
        let vmURL = VMLibraryController.shared.libraryURL
            .appendingPathComponent(data.name)
            .appendingPathExtension(VBVirtualMachine.bundleExtension)

        let model: VBVirtualMachine
        if let linuxInstallerURL = data.installImageURL, #available(macOS 13, *) {
            model = try VBVirtualMachine(creatingAtURL: vmURL, linuxInstallerURL: linuxInstallerURL)
        } else {
            model = try VBVirtualMachine(bundleURL: vmURL)
        }
        
        self.machine = model
    }

    @MainActor
    private func startInstallation() async {
        switch machine?.configuration.systemType {
        case .mac:
            await startMacInstallation()
        case .linux:
            guard #available(macOS 13, *) else {
                state = .error("This configuration requires macOS 13")
                break
            }
            await startLinuxInstallation()
        case .none:
            state = .error("Missing VM model or system type")
        }
    }

    @available(macOS 13, *)
    @MainActor
    private func startLinuxInstallation() async {
        guard let installURL = data.installImageURL else {
            state = .error("Missing install image URL")
            return
        }

        guard let model = machine else {
            state = .error("Missing VM model")
            return
        }

        do {
            let config = try await VMInstance.makeConfiguration(for: model, installImageURL: installURL)
            do {
                try config.validate()
            } catch {
                throw Failure("Failed to validate configuration: \(String(describing: error))")
            }
            
            step = .done
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @MainActor
    private func startMacInstallation() async { // TODO: handle Linux installation
        guard let restoreURL = data.restoreImageURL else {
            state = .error("Missing restore image URL")
            return
        }
        
        guard let model = machine else {
            state = .error("Missing VM model")
            return
        }

        do {
            state = .loading(nil, "Preparing Installation…\nThis may take a moment…")

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
                        self.machine?.metadata.installFinished = true
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
            guard step == .restoreImageInput else { return }

            validateCustomURL()
        }
    }

    private let allowedCustomDownloadSchemes: Set<String> = [
        "http",
        "https",
        "ftp"
    ]

    private func validateCustomURL() {
        let isValid = isCustomURLValid()
        disableNextButton = !isValid
    }

    private func isCustomURLValid() -> Bool {
        guard !provisionalRestoreImageURL.isEmpty else {
            return false
        }
        guard let url = URL(string: provisionalRestoreImageURL) else {
            return false
        }

        guard let scheme = url.scheme else {
            return false
        }

        guard allowedCustomDownloadSchemes.contains(scheme.lowercased()) else {
            return false
        }

        return true
    }

    func selectInstallFile() {
        let acceptedFiles: Set<UTType>
        if #available(macOS 13, *) {
            acceptedFiles = [.ipsw, .iso]
        } else {
            acceptedFiles = [.ipsw]
        }
        guard let url = NSOpenPanel.run(accepting: acceptedFiles) else {
            return
        }

        continueWithLocalFile(at: url)
    }

    func continueWithLocalFile(at url: URL) {
        if let fileType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            switch fileType {
            case .ipsw:
                data.restoreImageURL = url
            case .iso:
                data.installImageURL = url
            default:
                break
            }
        }

        step = .name
    }

    private func cleanupInstallerArtifacts() {
        progressObservation?.invalidate()
        progressObservation = nil

        vmInstaller = nil
    }

}

extension UTType {
    static let ipsw = UTType(filenameExtension: "ipsw")!
    static let iso = UTType(filenameExtension: "iso")!
}
