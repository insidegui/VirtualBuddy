import SwiftUI
import VirtualCore
import Combine
import OSLog

/// Controls active virtual machine sessions, managing the lifecycle of session windows, controllers, and opening VMs from files or URLs.
public final class VirtualMachineSessionUIManager: ObservableObject {
    private let logger = Logger(for: VirtualMachineSessionUIManager.self)
    
    public let focusedSessionChanged = PassthroughSubject<VirtualMachineSessionUI?, Never>()

    public static let shared = VirtualMachineSessionUIManager()

    private let openWindow = OpenCocoaWindowAction.default

    private var sessions = [VBVirtualMachine.ID: VirtualMachineSessionUI]()

    private init() { }

    @MainActor
    private func createSession(for vm: VBVirtualMachine, options: VMSessionOptions?) -> VirtualMachineSessionUI {
        let ui = VirtualMachineSessionUI(with: vm, options: options)
        
        sessions[vm.id] = ui

        return ui
    }

    @MainActor
    public func session(for vm: VBVirtualMachine) -> VirtualMachineSessionUI? { sessions[vm.id] }

    @MainActor
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

    @MainActor
    private func launchNewSession(for vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) {
        let vmID = vm.id

        let session = createSession(for: vm, options: options)

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

    @MainActor
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
            launchInstallWizard(restoring: vm, library: library)
        case .alertSecondButtonReturn:
            library.performMoveToTrash(for: vm)
        default:
            break
        }
    }

    @MainActor
    public func launchInstallWizard(restoring restoreVM: VBVirtualMachine? = nil, library: VMLibraryController) {
        openWindow {
            VMInstallationWizard(restoring: restoreVM)
                .environmentObject(library)
        }
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
                throw Failure("Unsupported file type \(values.contentType?.identifier ?? "?")")
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
