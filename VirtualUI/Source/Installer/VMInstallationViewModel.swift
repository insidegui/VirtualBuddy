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

@MainActor
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
        case .systemType, .configuration, .install:
            false
        case .restoreImageInput, .restoreImageSelection, .name, .done:
            true
        case .download:
            if case .failed = downloadState {
                true
            } else {
                false
            }
        }
    }

    @Published private(set) var buttonTitle = "Continue"
    @Published private(set) var showNextButton = true
    @Published  var disableNextButton = false

    private let library: VMLibraryController

    init(library: VMLibraryController, restoring restoreVM: VBVirtualMachine?) {
        self.library = library
        /// Skip OS selection if there's only a single supported OS.
        step = VBGuestType.supportedByHost.count > 1 ? .systemType : .restoreImageSelection

        if let restoreVM {
            restoreInstallation(with: restoreVM)
        }
    }

    init(library: VMLibraryController, restoringAt restoreURL: URL?, initialStep: Step? = nil) {
        self.library = library
        /// Skip OS selection if there's only a single supported OS.
        step = initialStep ?? (VBGuestType.supportedByHost.count > 1 ? .systemType : .restoreImageSelection)

        if let restoreURL {
            restoreInstallation(with: restoreURL)
        }
    }

    private func restoreInstallation(with url: URL) {
        do {
            let vm = try VBVirtualMachine(bundleURL: url)

            restoreInstallation(with: vm)
        } catch {
            assertionFailure("Couldn't restore install: \(error)")
            NSAlert(error: error).runModal()
        }
    }

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

    private var preventTerminationAssertion: PreventTerminationAssertion?

    private func startPreventingAppTermination(forReason reason: String) {
        stopPreventingAppTermination()

        preventTerminationAssertion = NSApp.preventTermination(forReason: reason)
    }

    private func stopPreventingAppTermination() {
        preventTerminationAssertion?.invalidate()
        preventTerminationAssertion = nil
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
    @Published private(set) var downloadState: DownloadState = .idle

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
        case .systemType, .configuration, .install, .done:
            break
        case .restoreImageInput:
            selectInstallMethod(.remoteOptions)
        case .restoreImageSelection:
            data.backgroundHash = .virtualBuddyBackground
            step = .systemType
        case .download:
            step = .restoreImageSelection
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

                do {
                    try prepareModel()
                } catch {
                    state = .error("Failed to prepare VM model: \(error.localizedDescription)")
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

    private var downloadURL: URL? {
        #if DEBUG
        guard let url = data.downloadURL else {
            if ProcessInfo.isSwiftUIPreview {
                return .catalogPlaceholder
            } else {
                assertionFailure("Expected download URL to be available for download")
                return nil
            }
        }

        return url
        #else
        return data.downloadURL
        #endif
    }

    private func setupDownload() {
        guard let url = downloadURL else {
            return
        }

        /// Run TSS check before download to prevent user from spending the time/bandwidth to download a build that will not install successfully.
        if data.systemType == .mac, VBSettings.current.enableTSSCheck {
            UILog("Requesting TSS check before download.")

            Task {
                downloadState = .preCheck("Checking Signing Status")

                let status = await VBAPIClient.shared.signingStatus(for: url)

                switch status {
                case .signed:
                    UILog("TSS check signed, proceeding with download.")

                    startDownload(with: url)
                case .unsigned(let message):
                    UILog("TSS check UNSIGNED, failing now.")

                    downloadState = .failed(message)
                    stopPreventingAppTermination()
                case .checkFailed:
                    /// Performing the check itself failed is ignored to avoid server-side issues preventing users from downloading/installing macOS.
                    UILog("Ignoring check failed TSS status.")

                    startDownload(with: url)
                }
            }
        } else {
            startDownload(with: url)
        }
    }

    private func startDownload(with url: URL) {
        let backend = createDownloadBackend(cookie: data.cookie)

        backend.statePublisher.assign(to: &$downloadState)

        self.downloader = backend

        backend.statePublisher
            .receive(on: DispatchQueue.main)
            .sink
        { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .done(let localURL):
                stopPreventingAppTermination()

                self.handleDownloadCompleted(with: localURL)
            case .failed(let message):
                stopPreventingAppTermination()
            case .idle, .preCheck, .downloading:
                break
            }
        }.store(in: &cancellables)

        startPreventingAppTermination(forReason: "downloading operating system image")

        backend.startDownload(with: url)
    }

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

    private func updateModelInstallerURL(with newURL: URL) throws {
        assert(machine != nil || ProcessInfo.isSwiftUIPreview, "This method requires the VM model to be available")
        assert(newURL.isFileURL || ProcessInfo.isSwiftUIPreview, "This method should be updating the installer URL with a local file URL, not a remote one!")
        guard var machine else { return }

        data.commitLocalRestoreImageURL(newURL)

        machine.metadata.updateRestoreImageURLs(with: data)

        try machine.saveMetadata()
    }

    private func startInstallation() async {
        switch machine?.configuration.systemType {
        case .mac:
            startMacInstallation()
        case .linux:
            await startLinuxInstallation()
        case .none:
            state = .error("Missing VM model or system type")
        }
    }

    @available(macOS 13, *)
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

    @Published private(set) var virtualMachine: VZVirtualMachine? = nil

    private var installationTask: Task<Void, Never>?

    private func startMacInstallation() {
        installationTask = Task { await _runMacInstallation() }
    }

    private func _runMacInstallation() async {
        guard let restoreURL = data.localRestoreImageURL else {
            state = .error("Missing local restore image URL")
            return
        }

        guard let model = machine else {
            state = .error("Missing VM model")
            return
        }

        state = .loading(nil, "Preparing Installation\nThis may take a moment")

        let backend = createRestoreBackend(for: model, restoreURL: restoreURL)
        installer = backend

        if let realBackend = backend as? VirtualizationRestoreBackend {
            realBackend.virtualMachine.assign(to: &$virtualMachine)
        }

        progressObservation = backend.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                let percent = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                self.state = .loading(percent, nil)
            }
        }

        @Sendable func cleanup() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stopPreventingAppTermination()
                self.library.loadMachines()
                self.installationTask = nil
                self.cleanupInstallerArtifacts()
            }
        }

        defer { cleanup() }

        await withTaskCancellationHandler {
            do {
                startPreventingAppTermination(forReason: "restoring virtual machine")

                try await backend.install()

                try Task.checkCancellation()

                self.machine?.metadata.installFinished = true

                self.step = .done

                UILog("Installation task finished successfully")
            } catch is CancellationError {
            } catch {
                UILog("Installation task finished with error \(error)")

                self.state = .error(error.localizedDescription)
            }
        } onCancel: {
            UILog("Installation task cancelled")
            cleanup()
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
        UILog(#function)
        
        progressObservation?.invalidate()
        progressObservation = nil

        virtualMachine = nil
        installer = nil
    }

    var confirmBeforeClosing: () async -> Bool {
        { [weak self] in
            guard let self else { return true }

            guard self.needsConfirmationBeforeClosing else { return true }

            let confirmed = await NSAlert.runConfirmationAlert(
                title: "Cancel Installation?",
                message: "If you close the window now, the virtual machine will not be ready for use. You can continue the installation later.",
                continueButtonTitle: "Cancel Installation",
                cancelButtonTitle: "Continue"
            )

            guard confirmed else { return false }

            await cancelInstallation()

            return true
        }
    }

    func cancelInstallation() async {
        UILog(#function)

        downloader?.cancelDownload()
        downloader = nil
        await installer?.cancel()
        installationTask?.cancel()
    }

    private var needsConfirmationBeforeClosing: Bool {
        guard step.needsConfirmationBeforeClosing else { return false }

        return switch step {
        case .download:
            switch downloadState {
            case .preCheck, .downloading: true
            default: false
            }
        default: true
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

