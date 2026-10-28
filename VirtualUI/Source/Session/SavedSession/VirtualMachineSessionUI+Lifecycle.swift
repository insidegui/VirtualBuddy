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

    /// The virtual machine's own close behavior when it has one, the global setting otherwise.
    var closeBehavior: VMCloseBehavior {
        let settings = VBSettingsContainer.current.settings

        guard let ui else { return settings.closeBehavior }

        return ui.controller.virtualMachineModel.configuration.closeBehavior(defaultingTo: settings)
    }

    func chooseCloseAction(context: SessionCloseContext) async -> SessionCloseChoice? {
        let hasOwnBehavior = ui?.controller.virtualMachineModel.configuration.closeBehaviorOverride != nil

        guard let result = await SavedSessionPrompts.chooseCloseAction(machine: name, defaultAppliesToMachineOnly: hasOwnBehavior, from: window) else {
            return nil
        }

        if result.makeDefault {
            ui?.rememberCloseBehavior(for: result.choice)
        }

        return result.choice
    }

    func confirmShutDownInsteadOfSaving(reason: String?, context: SessionCloseContext) async -> SessionCloseChoice? {
        /// Keeping the virtual machine running is only a way out of closing a window. Saving and closing, as well as quitting, end with it stopped.
        let offersKeepRunning = context == .window

        return await SavedSessionPrompts.confirmShutDownInsteadOfSaving(name: name, reason: reason, offersKeepRunning: offersKeepRunning, from: window)
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

    /// Saves the virtual machine (or shuts it down if saving isn't available), so that its window can close or the app can quit,
    /// or lets it keep running without a window if that's what the user prefers.
    /// See ``SessionCloseCoordinator``.
    func requestClose(context: SessionCloseContext = .window) async -> SessionCloseOutcome {
        await closer.requestClose(context: context)
    }

    /// Whether closing this session involves stopping a virtual machine.
    var needsStoppingBeforeClose: Bool { closer.needsStoppingBeforeClose }

    /// Saves the session and closes the window.
    func saveAndClose() async {
        guard await requestClose(context: .saveAndClose) == .stopped else { return }

        hostWindow?.close()
    }

    /// Makes the choice the user made when closing the window the default for the future.
    ///
    /// A virtual machine that has a close behavior of its own keeps having one, so the choice becomes that behavior.
    /// Otherwise, the global setting changes.
    func rememberCloseBehavior(for choice: SessionCloseChoice) {
        let behavior: VMCloseBehavior = switch choice {
        case .saveState: .saveState
        case .shutDown: .shutDown
        case .keepRunning: .keepRunning
        }

        if controller.virtualMachineModel.configuration.closeBehaviorOverride != nil {
            controller.virtualMachineModel.configuration.closeBehaviorOverride = behavior
        } else {
            VBSettingsContainer.current.settings.closeBehavior = behavior
        }
    }

    func forceStopAfterConfirmation() async {
        guard await SavedSessionPrompts.confirmForceStop(name: virtualMachine.name, from: hostWindow) else { return }

        do {
            try await controller.forceStop()
        } catch {
            NSApp.presentError(error)
        }
    }

    func forceStopAndClose() {
        (hostWindow as? HostingWindow)?.performAlternativeClose()
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

extension VirtualMachineSessionUI: AlternativeWindowClosing {
    func confirmAlternativeClose() async -> Bool {
        // An inactive VM still follows normal closing, preserving any saved session.
        guard needsStoppingBeforeClose else { return await requestClose() }
        guard controller.state.isRunning || controller.state.isPaused else { return false }
        guard await SavedSessionPrompts.confirmForceStopAndClose(name: virtualMachine.name, from: hostWindow) else { return false }

        do {
            try await controller.forceStop()
            return true
        } catch {
            NSApp.presentError(error)
            return false
        }
    }
}
