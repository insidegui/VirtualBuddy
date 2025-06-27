import SwiftUI
import VirtualCore
import Combine
import OSLog

/// Controls active virtual machine sessions, managing the lifecycle of session windows, controllers, and opening VMs from files or URLs.
@MainActor
public final class VirtualMachineSessionUIManager: ObservableObject {
    private let logger = Logger(for: VirtualMachineSessionUIManager.self)
    
    public let focusedSessionChanged = PassthroughSubject<WeakReference<VirtualMachineSessionUI>?, Never>()

    public static let shared = VirtualMachineSessionUIManager()

    private let openWindow = OpenCocoaWindowAction.default

    private var sessions = [VBVirtualMachine.ID: VirtualMachineSessionUI]()

    private init() { }

    private func createSession(for vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) -> VirtualMachineSessionUI {
        let ui = VirtualMachineSessionUI(with: vm, library: library, options: options)

        sessions[vm.id] = ui

        return ui
    }

    public func session(for vm: VBVirtualMachine) -> VirtualMachineSessionUI? { sessions[vm.id] }

    public func launch(_ vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) {
        guard !vm.needsInstall else {
            recoverInstallation(for: vm, library: library)
            return
        }

        if let existingSession = session(for: vm) {
            existingSession.update(with: options)
            existingSession.bringToFront()
        } else {
            launchNewSession(for: vm, library: library, options: options)
        }
    }

    private func launchNewSession(for vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) {
        let vmID = vm.id

        let session = createSession(for: vm, library: library, options: options)

        openWindow(id: vmID) {
            VirtualMachineSessionView()
                .environmentObject(session)
                .environmentObject(session.controller)
                .environmentObject(library)
                .environmentObject(self)
        } onClose: { [weak self] in
            guard let self else { return }
            guard let session = sessions[vmID] else { return }

            VBMemoryLeakDebugAssertions.vb_objectShouldBeReleasedSoon(session)
            VBMemoryLeakDebugAssertions.vb_objectShouldBeReleasedSoon(session.controller)

            sessions[vmID] = nil
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

    func handleOpenSavedStateFile(_ url: URL, library: VMLibraryController) {
        guard #available(macOS 14.0, *) else {
            let alert = NSAlert()
            alert.messageText = "State Restoration Not Supported"
            alert.informativeText = "Virtual machine state restoration requires macOS 14 or later."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        do {
            let model = try library.virtualMachine(forSavedStatePackageURL: url)

            let options = VMSessionOptions(stateRestorationPackageURL: url)

            launch(model, library: library, options: options)
        } catch {
            NSAlert(error: error).runModal()
        }
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
