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

struct VMInstallData: Hashable, Codable {
    @DecodableDefault.EmptyPlaceholder
    var systemType: VBGuestType = .empty

    @DecodableDefault.EmptyPlaceholder
    var installMethod: InstallMethod = .empty

    var backgroundHash: BlurHashToken = .virtualBuddyBackground

    var name = RandomNameGenerator.shared.newName()
    var cookie: String?
    var restoreImageInfo: RestoreImage? {
        didSet {
            if let url = restoreImageInfo?.url {
                installImageURL = url
            }
        }
    }
    var resolvedRestoreImage: ResolvedRestoreImage? {
        didSet { restoreImageInfo = resolvedRestoreImage?.image }
    }

    @DecodableDefault.EmptyString
    var inputInstallImageURL: String = ""

    var installImageURL: URL?

    var downloadURL: URL? { installImageURL ?? restoreImageInfo?.url }

    enum CodingKeys: String, CodingKey {
        case name, restoreImageInfo, installImageURL, systemType, installMethod
    }
}

extension VMInstallData {
    func canContinue(from step: VMInstallationStep) -> Bool {
        switch step {
        case .systemType: true
        case .restoreImageInput:
            true // TODO: Implement
        case .restoreImageSelection: resolvedRestoreImage != nil
        case .name: !name.isEmpty
        case .configuration:
            true // TODO: Implement
        case .download:
            true // TODO: Implement
        case .install:
            true // TODO: Implement
        case .done:
            true // TODO: Implement
        }
    }
}

extension VMInstallData {
    private static let allowedCustomDownloadSchemes: Set<String> = [
        "http",
        "https",
        "ftp"
    ]

    func validateCustomRestoreImageURL(_ input: String) -> Bool {
        guard !input.isEmpty else {
            return false
        }
        guard let url = URL(string: input) else {
            return false
        }

        guard let scheme = url.scheme else {
            return false
        }

        guard Self.allowedCustomDownloadSchemes.contains(scheme.lowercased()) else {
            return false
        }

        return true
    }

    mutating func commitCustomRestoreImageURL() throws {
        guard installMethod == .remoteManual else { return }
        
        guard let url = URL(string: inputInstallImageURL) else {
            throw Failure("Not a valid URL: \"\(inputInstallImageURL)\".")
        }

        self.installImageURL = url
    }
}

public enum VMInstallationStep: Int, Hashable, Codable {
    case systemType
    case restoreImageInput
    case restoreImageSelection
    case name
    case configuration
    case download
    case install
    case done
}

extension VMInstallationStep {
    var subtitle: String {
        switch self {
        case .systemType: "Choose Operating System"
        case .restoreImageInput: "Select Custom Restore Image"
        case .restoreImageSelection: "Choose Version"
        case .name: "Name Your Virtual Machine"
        case .configuration: "Configure Your Virtual Machine"
        case .download: "Downloading"
        case .install: "Installing"
        case .done: "Finished"
        }
    }
}

final class VMInstallationViewModel: ObservableObject, @unchecked Sendable {

    struct RestorableState: Codable {
        var data: VMInstallData
        var step: Step
    }

    typealias Step = VMInstallationStep

    enum State: Hashable {
        case idle
        case loading(_ progress: Double?, _ info: String?)
        case error(_ message: String)
    }

    private var restorableState: RestorableState {
        RestorableState(
            data: self.data,
            step: self.step
        )
    }

    @Published var machine: VBVirtualMachine?

    @Published var data = VMInstallData() {
        didSet {
            guard data != oldValue else { return }
            validate()
        }
    }

    @Published private(set) var state = State.idle

    @Published var step = Step.systemType {
        didSet {
            guard step != oldValue else { return }

            performActions(for: step)

            writeRestorationData()
        }
    }

    var canGoBack: Bool {
        switch step {
        case .systemType, .configuration, .download, .install, .done:
            false
        case .restoreImageInput, .restoreImageSelection, .name:
            true
        }
    }

    @Published private(set) var buttonTitle = "Continue"
    @Published private(set) var showNextButton = true
    @Published  var disableNextButton = false

    private let library: VMLibraryController

    @MainActor
    init(library: VMLibraryController, restoring restoreVM: VBVirtualMachine?) {
        self.library = library
        /// Skip OS selection if there's only a single supported OS.
        step = VBGuestType.supportedByHost.count > 1 ? .systemType : .restoreImageSelection

        if let restoreVM {
            restoreInstallation(with: restoreVM)
        }
    }

    @MainActor
    init(library: VMLibraryController, restoringAt restoreURL: URL?, initialStep: Step? = nil) {
        self.library = library
        /// Skip OS selection if there's only a single supported OS.
        step = initialStep ?? (VBGuestType.supportedByHost.count > 1 ? .systemType : .restoreImageSelection)

        if let restoreURL {
            restoreInstallation(with: restoreURL)
        }
    }

    @MainActor
    private func restoreInstallation(with url: URL) {
        do {
            let vm = try VBVirtualMachine(bundleURL: url)

            restoreInstallation(with: vm)
        } catch {
            assertionFailure("Couldn't restore install: \(error)")
            NSAlert(error: error).runModal()
        }
    }

    @MainActor
    private func restoreInstallation(with vm: VBVirtualMachine) {
        do {
            guard let restoreData = vm.installRestoreData else {
                throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "VM is missing install restore data"])
            }

            var restoredState = try PropertyListDecoder.virtualBuddy.decode(RestorableState.self, from: restoreData)
            if let restoreImage = restoredState.data.restoreImageInfo {
                restoredState.data.resolvedRestoreImage = try vm.resolveCatalogImage(restoreImage)
            }

            self.data = restoredState.data
            self.machine = vm
            self.step = restoredState.step
        } catch {
            assertionFailure("Couldn't restore install: \(error)")
            NSAlert(error: error).runModal()
        }
    }

    private func writeRestorationData() {
        guard var machine else { return }

        do {
            let restoreData = try PropertyListEncoder.virtualBuddy.encode(restorableState)
            machine.installRestoreData = restoreData
            try machine.saveMetadata()
            self.machine = machine
        } catch {
            assertionFailure("Failed to save install restore data: \(error)")
        }
    }

    private var needsDownload: Bool {
        guard let url = data.installImageURL else { return true }
        return !url.isFileURL
    }

    @Published private(set) var downloader: DownloadBackend?

    private func validate() {
        disableNextButton = !data.canContinue(from: step)
    }

    func next() {
        switch step {
            case .systemType:
                step = .restoreImageSelection
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

    func back() {
        guard canGoBack else { return }

        switch step {
        case .systemType, .configuration, .download, .install, .done:
            break
        case .restoreImageInput:
            setInstallMethod(.remoteOptions)
        case .restoreImageSelection:
            data.backgroundHash = .virtualBuddyBackground
            step = .systemType
        case .name:
            setInstallMethod(data.installMethod)
        }
    }

    private func performActions(for step: Step) {
        defer { validate() }

        switch step {
            case .systemType:
                showNextButton = true
            case .restoreImageInput:
                showNextButton = true
                validateCustomURL()
            case .restoreImageSelection:
                showNextButton = true
            case .name:
                commitCustomRestoreImageURL()

                showNextButton = true
            case .configuration:
                showNextButton = false

                Task {
                    do {
                        try await prepareModel()
                    } catch {
                        state = .error("Failed to prepare VM model: \(error.localizedDescription)")
                    }
                }
            case .download:
                showNextButton = false
                DispatchQueue.main.async { self.setupDownload() }
            case .install:
                Task { await startInstallation() }

                showNextButton = false
            case .done:
                showNextButton = true
                buttonTitle = "Back to Library"

                cleanupInstallerArtifacts()
        }
    }

    func setInstallMethod(_ method: InstallMethod) {
        data.installMethod = method

        commitInstallMethod()
    }

    private func commitInstallMethod() {
        switch data.installMethod {
        case .localFile:
            selectInstallFile()
        case .remoteOptions:
            step = .restoreImageSelection
        case .remoteManual:
            step = .restoreImageInput
        }
    }

    private func commitCustomRestoreImageURL() {
        do {
            try data.commitCustomRestoreImageURL()
        } catch {
            state = .error("\(error)")
        }
    }

    private func createDownloadBackend(cookie: String?) -> DownloadBackend {
        let Backend: DownloadBackend.Type
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "VBSimulateDownload") {
            Backend = SimulatedDownloadBackend.self
        } else {
            Backend = URLSessionDownloadBackend.self
        }
        #else
        Installer = URLSessionDownloadBackend.self
        #endif

        return Backend.init(library: library, cookie: cookie)
    }

    @MainActor
    private func setupDownload() {
        guard let url = data.downloadURL else {
            assertionFailure("Expected download URL to be available for download")
            return
        }

        let backend = createDownloadBackend(cookie: data.cookie)
        self.downloader = backend

        backend.statePublisher
            .receive(on: DispatchQueue.main)
            .sink
        { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .done(let localURL):
                self.handleDownloadCompleted(with: localURL)
            case .failed(let message):
                NSAlert(error: Failure(message)).runModal()
            default:
                break
            }
        }.store(in: &cancellables)

        backend.startDownload(with: url)
    }

    @MainActor
    func handleDownloadCompleted(with fileURL: URL) {
        downloader = nil

        data.installImageURL = fileURL

        do {
            try updateModelInstallerURL(with: fileURL)

            next()
        } catch {
            state = .error("Failed to update the virtual machine settings after downloading the installer. \(error)")
        }
    }

    private lazy var cancellables = Set<AnyCancellable>()

    private var vmInstaller: VMInstallationBackend?
    private var progressObservation: NSKeyValueObservation?

    @MainActor
    private func prepareModel() throws {
        let vmURL = library.libraryURL
            .appendingPathComponent(data.name)
            .appendingPathExtension(VBVirtualMachine.bundleExtension)

        let model: VBVirtualMachine

        switch data.systemType {
        case .mac:
            model = try VBVirtualMachine(bundleURL: vmURL, isNewInstall: true)
        case .linux:
            guard let url = data.installImageURL else {
                throw Failure("Installing a Linux virtual machine requires an install image URL")
            }
            model = try VBVirtualMachine(creatingAtURL: vmURL, linuxInstallerURL: url)
        }

        self.machine = model

        writeRestorationData()
    }

    @MainActor
    private func updateModelInstallerURL(with newURL: URL) throws {
        assert(machine != nil, "This method requires the VM model to be available")
        assert(newURL.isFileURL, "This method should be updating the installer URL with a local file URL, not a remote one!")
        guard var machine else { return }

        machine.metadata.installImageURL = newURL
        try machine.saveMetadata()
    }

    @MainActor
    private func startInstallation() async {
        switch machine?.configuration.systemType {
        case .mac:
            await startMacInstallation()
        case .linux:
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

    private func createInstaller(for vm: VZVirtualMachine, restoreURL: URL) -> VMInstallationBackend {
        let Backend: VMInstallationBackend.Type
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "VBSimulateInstall") {
            Backend = SimulatedVMInstallationBackend.self
        } else if restoreURL == SimulatedDownloadBackend.localFileURL {
            UILog("⚠️ Using simulated installer because the download was also simulated.")
            Backend = SimulatedVMInstallationBackend.self
        } else {
            Backend = VZMacOSInstaller.self
        }
        #else
        Installer = VZMacOSInstaller.self
        #endif

        return Backend.init(virtualMachine: vm, restoringFromImageAt: restoreURL)
    }

    @MainActor
    private func startMacInstallation() async {
        guard let restoreURL = data.installImageURL else {
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

            let installer = createInstaller(for: vm, restoreURL: restoreURL)
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


    @Published var provisionalRestoreImageURL = "" {
        didSet {
            guard step == .restoreImageInput else { return }

            validateCustomURL()
        }
    }

    private func validateCustomURL() {
        let isValid = data.validateCustomRestoreImageURL(provisionalRestoreImageURL)
        disableNextButton = !isValid
    }

    func selectInstallFile() {
        guard let url = NSOpenPanel.run(accepting: data.systemType.supportedRestoreImageTypes, defaultDirectoryKey: "restoreImage") else {
            setInstallMethod(.remoteOptions)
            return
        }

        continueWithLocalFile(at: url)
    }

    func continueWithLocalFile(at url: URL) {
        data.installImageURL = url

        step = .name
    }

    private func cleanupInstallerArtifacts() {
        progressObservation?.invalidate()
        progressObservation = nil

        vmInstaller = nil
    }

    var confirmBeforeClosing: () async -> Bool {
        { [weak self] in
            guard let self else { return true }

            guard self.step.needsConfirmationBeforeClosing else { return true }

            let confirmed = await NSAlert.runConfirmationAlert(
                title: "Cancel Installation?",
                message: "If you close the window now, the virtual machine will not be ready for use. You can continue the installation later.",
                continueButtonTitle: "Cancel Installation",
                cancelButtonTitle: "Continue"
            )

            guard confirmed else { return false }

            await MainActor.run {
                self.downloader?.cancelDownload()
                self.downloader = nil
                self.vmInstaller = nil
            }

            return true
        }
    }

}

private extension VMInstallationViewModel.Step {
    var needsConfirmationBeforeClosing: Bool {
        switch self {
        /// These steps are destructive if interrupted, so confirm before closing the wizard.
        case .configuration, .download, .install:
            return true
        default:
            return false
        }
    }
}

