import SwiftUI
import VirtualCore
import OSLog

/// Something a session is waiting for that isn't visible from the controller's state.
enum SessionActivity: Equatable {
    case shuttingDown
}

private let logger = Logger(for: VirtualMachineSessionUI.self)

/// Presents the questions that closing a session may need to ask, as alerts on the session's window.
@MainActor
final class SessionAlertPrompts: SessionClosePrompting {
    private weak var ui: VirtualMachineSessionUI?

    init(ui: VirtualMachineSessionUI) {
        self.ui = ui
    }

    private var name: String { ui?.virtualMachine.name ?? "Virtual Machine" }
    private var window: NSWindow? { ui?.hostWindow }

    var closeBehavior: VMCloseBehavior { SavedSessionPrompts.closeBehavior }

    func chooseCloseAction(context: SessionCloseContext) async -> SessionCloseChoice? {
        await SavedSessionPrompts.chooseCloseAction(machines: [name], quitting: context.isQuitting, from: window)
    }

    func confirmShutDownInsteadOfSaving(reason: String?, context: SessionCloseContext) async -> Bool {
        await SavedSessionPrompts.confirmShutDownInsteadOfSaving(name: name, reason: reason, quitting: context.isQuitting, from: window)
    }

    func presentSaveFailure(_ error: Error, context: SessionCloseContext) async -> SessionSaveFailureChoice {
        switch await SavedSessionPrompts.presentSaveFailure(name: name, error: error, quitting: context.isQuitting, from: window) {
        case .retry: .retry
        case .keepOpen: .keepOpen
        case .shutDown: .shutDown
        }
    }

    func confirmShutDown() async -> Bool {
        await SavedSessionPrompts.confirmShutDown(name: name, from: window)
    }

    func reportShutDownFailure(_ error: Error) {
        NSApp.presentError(error)
    }

    func setWaitingForShutdown(_ isWaiting: Bool) {
        ui?.setActivity(isWaiting ? .shuttingDown : nil)
    }
}

@MainActor
extension VirtualMachineSessionUI {

    // MARK: Closing

    /// Saves the virtual machine (or shuts it down if saving isn't available), so that its window can close or the app can quit.
    /// See ``SessionCloseCoordinator``.
    func requestClose(context: SessionCloseContext = .window) async -> Bool {
        await closer.requestClose(context: context)
    }

    /// Whether closing this session involves stopping a virtual machine.
    var needsStoppingBeforeClose: Bool { closer.needsStoppingBeforeClose }

    /// Saves the session and closes the window.
    func saveAndClose() async {
        guard await requestClose(context: .saveAndClose) else { return }

        hostWindow?.close()
    }

    func forceStopAfterConfirmation() async {
        guard await SavedSessionPrompts.confirmForceStop(name: virtualMachine.name, from: hostWindow) else { return }

        do {
            try await controller.forceStop()
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: Starting

    /// Starts the virtual machine, resuming its saved session if it has one.
    ///
    /// Anything that needs a decision from the user is presented here: a saved session that can't be restored,
    /// one that can't be continued with the selected boot options, and virtual machines that can't run side by side.
    func startOrResume() async {
        var discardingSavedSession = false

        while true {
            do {
                try await controller.start(discardingSavedSession: discardingSavedSession)
                return
            } catch SavedSessionError.discardConfirmationRequired {
                guard await SavedSessionPrompts.confirmDiscard(name: virtualMachine.name, startsAfterwards: true, from: hostWindow) else { return }

                discardingSavedSession = true
            } catch SavedSessionError.restoreFailed(let error) {
                logger.error("Failed to resume saved session: \(error, privacy: .public)")

                switch await SavedSessionPrompts.presentRestoreFailure(name: virtualMachine.name, error: error, from: hostWindow) {
                case .retry:
                    continue
                case .cancel:
                    return
                case .discardAndStart:
                    guard await SavedSessionPrompts.confirmDiscard(name: virtualMachine.name, startsAfterwards: true, from: hostWindow) else { return }

                    discardingSavedSession = true
                }
            } catch SavedSessionError.recoveryRequired {
                await reviewRecoveryOptions()
                return
            } catch SavedSessionError.activeCopyConflict(let conflicts) {
                if let conflict = await SavedSessionPrompts.presentActiveCopyConflict(name: virtualMachine.name, conflicts: conflicts, from: hostWindow) {
                    showSession(withID: conflict.virtualMachineID)
                }
                return
            } catch is CancellationError {
                return
            } catch {
                /// Failures to boot are shown by the session itself.
                logger.error("Failed to start: \(error, privacy: .public)")
                return
            }
        }
    }

    private func showSession(withID id: VBVirtualMachine.ID) {
        VirtualMachineSessionUIManager.shared.sessionIfAvailable(withID: id)?.bringToFront()
    }

    // MARK: Recovery

    /// Explains what's wrong with the saved session and lets the user decide what to do about it.
    func reviewRecoveryOptions() async {
        guard case .recoveryRequired(let issue) = controller.state else { return }

        let name = virtualMachine.name

        do {
            switch await SavedSessionPrompts.presentRecoveryOptions(name: name, issue: issue, from: hostWindow) {
            case .cancel:
                break
            case .showInFinder:
                NSWorkspace.shared.activateFileViewerSelecting([controller.virtualMachineModel.bundleURL])
            case .retryStop:
                try await controller.retryStopAfterSave()
            case .discard:
                guard await SavedSessionPrompts.confirmDiscard(name: name, startsAfterwards: false, from: hostWindow) else { return }
                try await controller.discardSavedSession()
            case .discardAndStart:
                guard await SavedSessionPrompts.confirmDiscard(name: name, startsAfterwards: true, from: hostWindow) else { return }
                try await controller.start(discardingSavedSession: true)
            case .reinstate:
                guard await SavedSessionPrompts.confirmReinstate(name: name, from: hostWindow) else { return }
                try await controller.reinstateInterruptedSavedSession()
            }
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Lets the user discard the saved session without starting the virtual machine.
    func discardSavedSessionAfterConfirmation() async {
        guard await SavedSessionPrompts.confirmDiscard(name: virtualMachine.name, startsAfterwards: false, from: hostWindow) else { return }

        do {
            try await controller.discardSavedSession()
        } catch {
            NSApp.presentError(error)
        }
    }
}
