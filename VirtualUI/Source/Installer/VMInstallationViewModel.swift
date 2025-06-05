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
import BuddyKit

struct VMInstallData: Hashable, Codable {
    // MARK: Persisted State

    @DecodableDefault.EmptyPlaceholder
    var systemType: VBGuestType = .empty

    var installMethod: InstallMethod { installMethodSelection?.id ?? .empty }

    var installMethodSelection: InstallMethodSelection? = nil

    var backgroundHash: BlurHashToken = .virtualBuddyBackground

    var name = RandomNameGenerator.shared.newName()

    /// URL to the local restore image that will be used to restore the VM.
    /// This will be the custom local file selected by the user, or the URL to the local file
    /// that's been downloaded from either a custom remote URL or a selected restore image option.
    private(set) var localRestoreImageURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        /// Cookie is not stored because it would end up in clear text on the file system when the struct is encoded...
        case systemType, installMethodSelection, backgroundHash, name, localRestoreImageURL
    }

    // MARK: Temporary State

    private(set) var selectedRestoreImage: RestoreImage? = nil
    var resolvedRestoreImage: ResolvedRestoreImage? = nil {
        didSet {
            selectedRestoreImage = resolvedRestoreImage?.image
        }
    }

    @DecodableDefault.EmptyString
    var customInstallImageRemoteURL: String = ""

    var cookie: String? = nil
}

// MARK: Convenience

extension VMInstallData {
    var downloadURL: URL? {
        switch installMethodSelection {
        case .remoteManual(let url): url
        case .remoteOptions(let image): image.url
        case .localFile: nil
        case .none: nil
        }
    }

    var needsDownload: Bool {
        UILog("[needsDownload] Method is \(installMethod), downloadURL is \(String(optional: downloadURL))")
        return downloadURL != nil
    }
}

// MARK: Updates / Validation

extension VMInstallData {
    func canContinue(from step: VMInstallationStep) -> Bool {
        switch step {
        case .systemType: true
        case .restoreImageInput: installMethodSelection != nil
        case .restoreImageSelection: selectedRestoreImage != nil
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

    private static let allowedCustomDownloadSchemes: Set<String> = [
        "http",
        "https",
        "ftp"
    ]

    func validateCustomRestoreImageRemoteURL() -> Bool {
        guard !customInstallImageRemoteURL.isEmpty else {
            return false
        }
        guard let url = URL(string: customInstallImageRemoteURL) else {
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

    mutating func commitSelectedRestoreImage() throws {
        UILog("\(#function) \(String(optional: selectedRestoreImage?.url.absoluteString.quoted))")

        installMethodSelection = try .remoteOptions(selectedRestoreImage.require("Please select one of the OS versions available."))
    }

    mutating func commitCustomRestoreImageURL() throws {
        UILog("\(#function) \(customInstallImageRemoteURL.quoted)")

        installMethodSelection = try .remoteManual(URL(string: customInstallImageRemoteURL).require("Invalid URL: \(customInstallImageRemoteURL.quoted)."))
    }

    mutating func commitCustomRestoreImageLocalFile(path: String) {
        UILog("\(#function) \(path.quoted)")

        let fileURL = URL(fileURLWithPath: path)
        installMethodSelection = .localFile(fileURL)
        commitLocalRestoreImageURL(fileURL)
    }

    @MainActor
    mutating func resolveCatalogImageIfNeeded(with model: VBVirtualMachine) throws {
        guard case .remoteOptions(let restoreImage) = installMethodSelection else { return }

        resolvedRestoreImage = try model.resolveCatalogImage(restoreImage)
    }

    mutating func commitLocalRestoreImageURL(_ url: URL) {
        localRestoreImageURL = url
    }

    /// Removes any data associated with the current install method selection if the new selection is a different install method.
    mutating func resetInstallMethodSelectionIfNeeded(selectedMethod: InstallMethod) {
        guard let installMethodSelection else { return }
        guard selectedMethod != installMethodSelection.id else { return }
        self.installMethodSelection = nil
        self.resolvedRestoreImage = nil
    }
}

extension VBVirtualMachine.Metadata {
    mutating func updateRestoreImageURLs(with data: VMInstallData) {
        /// Always save whatever URL the restore image was downloaded from and the local file URL, regardless of the install method.
        if let downloadURL = data.downloadURL {
            updateInstallImageURL(downloadURL)
        }
        if let localRestoreImageURL = data.localRestoreImageURL {
            updateInstallImageURL(localRestoreImageURL)
        }
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
    private func restoreInstallation(with model: VBVirtualMachine) {
        do {
            guard let restoreData = model.installRestoreData else {
                throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "VM is missing install restore data"])
            }

            var restoredState = try PropertyListDecoder.virtualBuddy.decode(RestorableState.self, from: restoreData)
            try restoredState.data.resolveCatalogImageIfNeeded(with: model)

            self.data = restoredState.data
            self.machine = model
            self.step = restoredState.step
        } catch {
            assertionFailure("Couldn't restore install: \(error)")
            NSAlert(error: error).runModal()
        }
    }

    private func writeRestorationData() {
        guard var machine else { return }

        machine.metadata.updateRestoreImageURLs(with: data)

        do {
            let restoreData = try PropertyListEncoder.virtualBuddy.encode(restorableState)
            machine.installRestoreData = restoreData
            try machine.saveMetadata()
            self.machine = machine
        } catch {
            assertionFailure("Failed to save install restore data: \(error)")
        }
    }

    @Published private(set) var downloader: DownloadBackend?

    private func validate() {
        disableNextButton = !data.canContinue(from: step)
    }

    func next() {
        switch step {
        case .systemType:
            step = .restoreImageSelection
        case .restoreImageInput:
            commitCustomRestoreImageURL()

            step = .name
        case .restoreImageSelection:
            commitSelectedRestoreImage()

            step = .name
        case .name:
            step = .configuration
        case .configuration:
            step = data.needsDownload ? .download : .install
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
            selectInstallMethod(.remoteOptions)
        case .restoreImageSelection:
            data.backgroundHash = .virtualBuddyBackground
            step = .systemType
        case .name:
            /// Re-trigger any UI prompts associated with the install method, such as entering remote URL or selecting local file.
            selectInstallMethod(data.installMethod)
        }
    }

    private func performActions(for step: Step) {
        defer { validate() }

        switch step {
            case .systemType:
                showNextButton = true
            case .restoreImageInput:
                showNextButton = true
                validateCustomRemoteURL()
            case .restoreImageSelection:
                showNextButton = true
            case .name:
                showNextButton = true
            case .configuration:
                showNextButton = true

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

    func selectInstallMethod(_ method: InstallMethod) {
        UILog("\(#function) \(method)")

        data.resetInstallMethodSelectionIfNeeded(selectedMethod: method)
        
        switch method {
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

    private func commitSelectedRestoreImage() {
        guard data.installMethod != .localFile, data.installMethod != .remoteManual else { return }
        
        do {
            try data.commitSelectedRestoreImage()
        } catch {
            state = .error("\(error)")
        }
    }

    private func createDownloadBackend(cookie: String?) -> DownloadBackend {
        let Backend: DownloadBackend.Type
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "VBSimulateDownload") || ProcessInfo.isSwiftUIPreview {
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

        do {
            try updateModelInstallerURL(with: fileURL)

            next()
        } catch {
            state = .error("Failed to update the virtual machine settings after downloading the installer. \(error)")
        }
    }

    private lazy var cancellables = Set<AnyCancellable>()

    private var installer: RestoreBackend?
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
            model = try VBVirtualMachine(creatingLinuxMachineAt: vmURL)
        }

        self.machine = model

        writeRestorationData()
    }

    @MainActor
    private func updateModelInstallerURL(with newURL: URL) throws {
        assert(machine != nil, "This method requires the VM model to be available")
        assert(newURL.isFileURL, "This method should be updating the installer URL with a local file URL, not a remote one!")
        guard var machine else { return }

        data.commitLocalRestoreImageURL(newURL)

        machine.metadata.updateRestoreImageURLs(with: data)

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
        guard let installURL = data.localRestoreImageURL else {
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
    private func createRestoreBackend(for model: VBVirtualMachine, restoreURL: URL) -> RestoreBackend {
        let Backend: RestoreBackend.Type
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "VBSimulateInstall") || ProcessInfo.isSwiftUIPreview {
            Backend = SimulatedRestoreBackend.self
        } else if restoreURL == SimulatedDownloadBackend.localFileURL {
            UILog("⚠️ Using simulated installer because the download was also simulated.")
            Backend = SimulatedRestoreBackend.self
        } else {
            Backend = VirtualizationRestoreBackend.self
        }
        #else
        Installer = VirtualizationRestoreBackend.self
        #endif

        return Backend.init(model: model, restoringFromImageAt: restoreURL)
    }

    @MainActor
    private func startMacInstallation() async {
        guard let restoreURL = data.localRestoreImageURL else {
            state = .error("Missing local restore image URL")
            return
        }

        guard let model = machine else {
            state = .error("Missing VM model")
            return
        }

        state = .loading(nil, "Preparing Installation…\nThis may take a moment…")

        let backend = createRestoreBackend(for: model, restoreURL: restoreURL)
        installer = backend

        progressObservation = backend.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                let percent = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                self.state = .loading(percent, "Installing macOS…")
            }
        }

        do {
            try await backend.install()

            self.machine?.metadata.installFinished = true

            self.step = .done
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    func validateCustomRemoteURL() {
        let isValid = data.validateCustomRestoreImageRemoteURL()
        disableNextButton = !isValid
    }

    func selectInstallFile() {
        guard let url = NSOpenPanel.run(accepting: data.systemType.supportedRestoreImageTypes, defaultDirectoryKey: "restoreImage") else {
            return
        }

        data.commitCustomRestoreImageLocalFile(path: url.path)

        next()
    }

    private func cleanupInstallerArtifacts() {
        progressObservation?.invalidate()
        progressObservation = nil

        installer = nil
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
                self.installer = nil
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

