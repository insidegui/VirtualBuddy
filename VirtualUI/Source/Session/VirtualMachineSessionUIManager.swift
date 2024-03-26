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
    public func launch(_ vm: VBVirtualMachine, library: VMLibraryController) {
        guard !vm.needsInstall else {
            recoverInstallation(for: vm, library: library)
            return
        }

        openWindow(id: vm.id) {
            VirtualMachineSessionView(controller: VMController(with: vm), ui: VirtualMachineSessionUI(with: vm))
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

    @MainActor
    public func openVirtualMachine(at url: URL, library: VMLibraryController) {
        do {
            let values = try url.resourceValues(forKeys: [.contentTypeKey])

            guard values.contentType == .virtualBuddyVM else {
                throw Failure("Invalid file type: \(String(describing: values.contentType))")
            }

            if let loadedVM = library.virtualMachines.first(where: { $0.bundleURL.path == url.path }) {
                launch(loadedVM, library: library)
            } else {
                let vm = try VBVirtualMachine(bundleURL: url)

                launch(vm, library: library)
            }
        } catch {
            logger.error("Error loading virtual machine from file at \(url.path, privacy: .public): \(error, privacy: .public)")
        }
    }

}
