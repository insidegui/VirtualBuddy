import Foundation
import VirtualCore
import VirtualUI

/// Finds virtual machines and their sessions for whatever controls the app from outside: deep links and the command-line tool.
///
/// Nothing here presents anything, so that each caller reports failures its own way.
@MainActor
final class VMAutomationService {
    let library: VMLibraryController
    let sessionManager: VirtualMachineSessionUIManager

    init(library: VMLibraryController, sessionManager: VirtualMachineSessionUIManager) {
        self.library = library
        self.sessionManager = sessionManager
    }

    func virtualMachine(named name: String) throws -> VBVirtualMachine {
        guard let vm = library.virtualMachine(named: name) else {
            throw Failure("Couldn't find a virtual machine with the name \(name.wrappedInSmartQuotes).")
        }
        return vm
    }

    /// Finds a virtual machine by its name, its identifier or the path of its bundle.
    func virtualMachine(matching reference: String) throws -> VBVirtualMachine {
        try VMReference.resolve(reference, in: library.virtualMachines, name: \.name, uuid: \.uuid, path: \.bundleURL.path)
    }

    /// The controller of a virtual machine that has a session, whether or not it's running.
    func controller(for vm: VBVirtualMachine) -> VMController? {
        library.activeController(for: vm.id)
    }

    func controller(forVMNamed name: String) throws -> VMController {
        let vm = try virtualMachine(named: name)
        guard let controller = controller(for: vm) else {
            throw Failure("Couldn't find active instance of virtual machine with the name \(name.wrappedInSmartQuotes).")
        }
        return controller
    }

    /// Opens the virtual machine's window, or brings it to the front. An installation that didn't finish is offered to be continued instead.
    func open(_ vm: VBVirtualMachine, options: VMSessionOptions?) {
        sessionManager.launch(vm, library: library, options: options)
    }

    /// The virtual machine's session, opening its window when it doesn't have one yet.
    func session(for vm: VBVirtualMachine) throws -> VirtualMachineSessionUI {
        if let session = sessionManager.session(for: vm) { return session }
        sessionManager.launch(vm, library: library, options: nil)
        guard let session = sessionManager.session(for: vm) else {
            throw Failure("Couldn't open the virtual machine \(vm.name.wrappedInSmartQuotes).")
        }
        return session
    }

    /// Asks the guest to shut down.
    func stop(named name: String) async throws {
        let controller = try controller(forVMNamed: name)

        switch controller.state {
        case .idle, .stopped, .saved, .recoveryRequired:
            throw Failure("Can't stop virtual machine \(name.wrappedInSmartQuotes) because it's not running.")
        default:
            try await controller.stop()
        }
    }
}
