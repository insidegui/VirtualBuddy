import SwiftUI
import VirtualCore
import Combine
import OSLog

/// Controls active virtual machine sessions, managing the lifecycle of session windows, controllers, and opening VMs from files or URLs.
///
/// A session normally lives as long as its window. A virtual machine can also keep running after its window is closed,
/// in which case the session stays around without a window until the virtual machine stops or the window is opened again from the library.
@MainActor
public final class VirtualMachineSessionUIManager: ObservableObject {
    private let logger = Logger(for: VirtualMachineSessionUIManager.self)
    
    public let focusedSessionChanged = PassthroughSubject<WeakReference<VirtualMachineSessionUI>?, Never>()

    public static let shared = VirtualMachineSessionUIManager()

    private let openWindow = OpenCocoaWindowAction.default

    @Published private(set) var sessions = [VBVirtualMachine.ID: VirtualMachineSessionUI]()

    /// Sessions whose virtual machine is running without a window.
    @Published public private(set) var backgroundSessionIDs = Set<VBVirtualMachine.ID>()

    /// Ends background sessions once their virtual machine stops.
    private var backgroundSessionObservations = [VBVirtualMachine.ID: AnyCancellable]()

    private let terminationPresenter = TerminationPresenter()

    /// Decides whether the app may quit while virtual machines are running. See `prepareForTermination()`.
    private(set) lazy var terminationCoordinator = SessionTerminationCoordinator(
        presenter: terminationPresenter,
        holdTermination: { Self.holdTermination() }
    )

    private init() {
        terminationPresenter.manager = self
    }

    private func createSession(for vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) -> VirtualMachineSessionUI {
        let ui = VirtualMachineSessionUI(with: vm, library: library, options: options)

        ui.controller.macAddressConflictHandler = { [weak self] conflicts in
            guard let self else { return .cancel }
            return await self.presentMACAddressConflictAlert(conflicts: conflicts)
        }

        sessions[vm.id] = ui

        return ui
    }

    public func session(for vm: VBVirtualMachine) -> VirtualMachineSessionUI? { sessions[vm.id] }

    func sessionIfAvailable(withID id: VBVirtualMachine.ID) -> VirtualMachineSessionUI? { sessions[id] }

    /// Whether the virtual machine is running without a window.
    public func isRunningInBackground(_ vm: VBVirtualMachine) -> Bool { backgroundSessionIDs.contains(vm.id) }

    /// Opens the virtual machine's window, creating a session for it if it doesn't have one.
    /// A virtual machine that's running in the background gets its window back.
    public func launch(_ vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) {
        guard !vm.needsInstall else {
            recoverInstallation(for: vm, library: library)
            return
        }

        if let existingSession = session(for: vm) {
            existingSession.update(with: options)

            if openWindow.hasWindow(for: vm.id) {
                existingSession.bringToFront()
            } else {
                showWindow(for: existingSession, library: library)
            }
        } else {
            let session = createSession(for: vm, library: library, options: options)

            showWindow(for: session, library: library)
        }
    }

    private func presentMACAddressConflictAlert(conflicts: [MACAddressConflict]) async -> MACAddressConflictResolution {
        let alert = NSAlert()
        alert.messageText = "Duplicate MAC Address"
        let formattedConflicts = conflicts
            .sorted { $0.macAddress < $1.macAddress }
            .map { "\($0.macAddress) used by \"\($0.vmName)\"" }
            .joined(separator: "\n")
        alert.informativeText = "A network device on this virtual machine shares a MAC address with another virtual machine that's already running:\n\n\(formattedConflicts)\n\nRunning multiple virtual machines with the same MAC address may cause network connectivity issues."
        alert.addButton(withTitle: "Randomize MAC address & Continue")
        alert.addButton(withTitle: "Continue Anyway")
        alert.addButton(withTitle: "Cancel")

        let response: NSApplication.ModalResponse
        if let window = NSApp?.keyWindow {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }

        switch response {
        case .alertFirstButtonReturn: return .randomize
        case .alertSecondButtonReturn: return .continueAnyway
        default: return .cancel
        }
    }

    // MARK: - Windows

    /// Opens a window for the session. A session that was running in the background is in the foreground from here on.
    private func showWindow(for session: VirtualMachineSessionUI, library: VMLibraryController) {
        let vmID = session.virtualMachine.id

        leaveBackground(vmID)

        openWindow(id: vmID) {
            VirtualMachineSessionView()
                .environmentObject(session)
                .environmentObject(session.controller)
                .environmentObject(library)
                .environmentObject(self)
        } onClose: { [weak self] in
            self?.handleWindowClosed(for: vmID)
        }
    }

    /// Decides whether a session's window may close, stopping the virtual machine or moving it to the background first.
    /// - Returns: `false` if the window has to stay open.
    func shouldCloseWindow(of session: VirtualMachineSessionUI) async -> Bool {
        switch await session.requestClose(context: .window) {
        case .cancelled:
            return false
        case .stopped:
            return true
        case .keptRunning:
            moveToBackground(session)
            return true
        }
    }

    private func handleWindowClosed(for vmID: VBVirtualMachine.ID) {
        guard let session = sessions[vmID] else { return }

        /// The virtual machine keeps running: its session outlives the window.
        guard !backgroundSessionIDs.contains(vmID) else {
            logger.debug("Window closed for \(vmID.shortID, privacy: .public), virtual machine keeps running in the background")
            return
        }

        VBMemoryLeakDebugAssertions.vb_objectShouldBeReleasedSoon(session)
        VBMemoryLeakDebugAssertions.vb_objectShouldBeReleasedSoon(session.controller)

        sessions[vmID] = nil
    }

    // MARK: - Background Sessions

    /// Keeps the session around without a window until its virtual machine stops.
    private func moveToBackground(_ session: VirtualMachineSessionUI) {
        let vmID = session.virtualMachine.id

        backgroundSessionIDs.insert(vmID)

        /// Only a change matters here: when this starts, the virtual machine may be running (closing its window)
        /// or not running yet (starting in the background), and neither is a reason to end the session.
        backgroundSessionObservations[vmID] = session.controller.$state
            .map(\.isActive)
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                /// The state changes in the middle of a controller operation. Ending the session, which may release the controller, waits for that to finish.
                Task { @MainActor [weak self] in
                    self?.endBackgroundSessionIfStopped(withID: vmID)
                }
            }
    }

    private func leaveBackground(_ vmID: VBVirtualMachine.ID) {
        backgroundSessionObservations[vmID] = nil
        backgroundSessionIDs.remove(vmID)
    }

    /// Ends a background session whose virtual machine isn't running anymore. There's no window to show what happened to it,
    /// so there's nothing left for the session to do.
    private func endBackgroundSessionIfStopped(withID vmID: VBVirtualMachine.ID) {
        guard backgroundSessionIDs.contains(vmID), let session = sessions[vmID] else { return }
        guard !session.controller.state.isActive else { return }
        guard !openWindow.hasWindow(for: vmID) else { return }

        logger.debug("Virtual machine \(vmID.shortID, privacy: .public) stopped while running in the background, ending its session")

        leaveBackground(vmID)

        VBMemoryLeakDebugAssertions.vb_objectShouldBeReleasedSoon(session)
        VBMemoryLeakDebugAssertions.vb_objectShouldBeReleasedSoon(session.controller)

        sessions[vmID] = nil
    }

    /// Starts every virtual machine that's configured to start when the app launches, without opening windows for them.
    ///
    /// Waits for the library to finish loading. Virtual machines are started one at a time to keep the load on the disks down.
    public func autoBootVirtualMachinesInBackground(library: VMLibraryController) async {
        guard let state = await library.$state.values.first(where: { $0.id != .loading }) else { return }

        guard case .loaded(let machines) = state else {
            logger.debug("Library isn't available, skipping virtual machines that start at launch")
            return
        }

        let candidates = machines.filter { $0.configuration.autoBootInBackground && !$0.needsInstall }

        guard !candidates.isEmpty else { return }

        logger.info("Starting \(candidates.count) virtual machine(s) in the background: \(candidates.map(\.name).formatted(.list(type: .and)), privacy: .public)")

        for vm in candidates {
            /// Something else (such as a deep link) may have opened the virtual machine in the meantime.
            guard session(for: vm) == nil else { continue }

            let session = createSession(for: vm, library: library, options: nil)

            moveToBackground(session)

            await session.startOrResume()

            /// A virtual machine that didn't start has no session worth keeping without a window.
            endBackgroundSessionIfStopped(withID: vm.id)
        }
    }

    public func recoverInstallation(for vm: VBVirtualMachine, library: VMLibraryController) {
        let alert = NSAlert()
        alert.messageText = "Finish Installation"
        alert.informativeText = "In order to start this virtual machine, its operating system needs to be installed. Would you like to install it now?"
        alert.addButton(withTitle: "Install")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let choice = alert.runModal()

        switch choice {
        case .alertFirstButtonReturn:
            launchInstallWizard(restoringAt: vm.bundleURL, library: library)
        case .alertSecondButtonReturn:
            library.performMoveToTrash(for: vm)
        default:
            break
        }
    }

    public func launchInstallWizard(restoringAt restoreURL: URL? = nil, library: VMLibraryController) {
        openWindow(animationBehavior: .documentWindow) {
            VMInstallationWizard(library: library, restoringAt: restoreURL)
                .environmentObject(library)
        }
    }

    public func launchImportVirtualMachinePanel(library: VMLibraryController) {
        guard let url = NSOpenPanel.run(accepting: VMImporterRegistry.default.supportedFileTypes, directoryURL: nil, defaultDirectoryKey: "importVirtualMachine", prompt: "Import") else {
            return
        }

        open(fileURL: url, library: library)
    }

    private func importVirtualMachine(from path: FilePath, using importer: any VMImporter, library: VMLibraryController) async {
        do {
            guard await confirmImport(using: importer) else {
                throw CancellationError()
            }

            logger.debug("Import authorized from \(importer.appName) - \(path)")

            var model = try await importer.importVirtualMachine(from: path, into: library)

            model.metadata.importedFromAppName = importer.appName

            try model.saveMetadata()

            library.reload()

            open(fileURL: model.bundleURL, library: library)
        } catch is CancellationError {
            logger.notice("Import cancelled")
        } catch {
            NSApp.presentError(error)
        }
    }

    private var importTask: Task<Void, Never>?

    private func beginImportVirtualMachine(from path: FilePath, using importer: any VMImporter, library: VMLibraryController) {
        importTask = Task {
            await importVirtualMachine(from: path, using: importer, library: library)
        }
    }

    func confirmImport(using importer: any VMImporter) async -> Bool {
        #if DEBUG
        guard !Self.testImportSkipConfirmation else { return true }
        #endif
        
        return await NSAlert
            .runConfirmationAlert(
                title: "Import From \(importer.appName)?",
                message: "VirtualBuddy will attempt to import your virtual machine from \(importer.appName). All data from this virtual machine in \(importer.appName) will be copied into your VirtualBuddy library. Would you like to proceed?",
                continueButtonTitle: "Import",
                cancelButtonTitle: "Cancel",
                continueButtonIsDefault: true
            )
    }
}

// MARK: - File Opening

@MainActor
public extension VirtualMachineSessionUIManager {
    func open(fileURL: URL, library: VMLibraryController) {
        do {
            let values = try fileURL.resourceValues(forKeys: [.contentTypeKey])

            switch values.contentType {
            case .none:
                return
            case .virtualBuddyVM:
                handleOpenVirtualMachineFile(fileURL, library: library, options: nil)
            case .virtualBuddySavedState:
                handleOpenSavedStateFile(fileURL, library: library)
            default:
                let path = FilePath(fileURL)

                if let importer = VMImporterRegistry.default.importer(for: path) {
                    beginImportVirtualMachine(from: path, using: importer, library: library)
                } else {
                    throw Failure("Unsupported file type \(values.contentType?.identifier ?? "?")")
                }
            }
        } catch {
            logger.error("Error loading virtual machine from file at \(fileURL.path, privacy: .public): \(error, privacy: .public)")
        }
    }
}

@MainActor
private extension VirtualMachineSessionUIManager {
    func handleOpenVirtualMachineFile(_ url: URL, library: VMLibraryController, options: VMSessionOptions?) {
        if let loadedVM = library.virtualMachines.first(where: { $0.bundleURL.path == url.path }) {
            launch(loadedVM, library: library, options: options)
        } else {
            do {
                let vm = try VBVirtualMachine(bundleURL: url)

                launch(vm, library: library, options: options)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    /// Saved states created by earlier versions can't be resumed safely, so they're only ever shown, never opened.
    func handleOpenSavedStateFile(_ url: URL, library: VMLibraryController) {
        SavedSessionPrompts.presentLegacySavedState(at: url)
    }
}

#if DEBUG
// MARK: - Import Testing (Debug)
@MainActor
extension VirtualMachineSessionUIManager {
    static let testImportSkipConfirmation = UserDefaults.standard.bool(forKey: "VBTestImportSkipConfirmation")
    static let testImportVMPath: FilePath? = UserDefaults.standard.string(forKey: "VBTestImport").flatMap { FilePath($0) }

    public func testImportVMIfEnabled(library: VMLibraryController) {
        guard let path = Self.testImportVMPath else { return }

        open(fileURL: path.url, library: library)
    }
}
#endif
