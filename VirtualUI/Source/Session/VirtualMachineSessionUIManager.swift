import SwiftUI
import VirtualCore
import Combine
import OSLog

public final class VirtualMachineSessionUIManager: ObservableObject {
    private let logger = Logger(for: VirtualMachineSessionUIManager.self)
    
    public let focusedSessionChanged = PassthroughSubject<VirtualMachineSessionUI?, Never>()

    public static let shared = VirtualMachineSessionUIManager()

    private let openWindow = OpenCocoaWindowAction.default

    private init() { }

    @MainActor
    public func launch(_ vm: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) {
        guard !vm.needsInstall else {
            recoverInstallation(for: vm, library: library)
            return
        }

        openWindow(id: vm.id) {
            VirtualMachineSessionView(controller: VMController(with: vm, options: options), ui: VirtualMachineSessionUI(with: vm))
                .environmentObject(library)
                .environmentObject(self)
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
                break
            }

            guard values.contentType == .virtualBuddyVM else {
                throw Failure("Invalid file type: \(String(describing: values.contentType))")
            }

            if let loadedVM = library.virtualMachines.first(where: { $0.bundleURL.path == fileURL.path }) {
                launch(loadedVM, library: library, options: nil)
            } else {
                let vm = try VBVirtualMachine(bundleURL: fileURL)

                launch(vm, library: library, options: nil)
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
