import Foundation
import OSLog

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "SessionLifecycle")

// MARK: - Protocols

/// Where a virtual machine is in its lifecycle, as far as closing and quitting are concerned.
public enum VMLifecycleStage: Equatable, Sendable {
    /// Nothing is running: it's off, or it's saved and ready to be resumed.
    case notRunning
    /// A session was saved, but needs a decision (and the virtual machine may still be around).
    case recoveryRequired(SavedSessionIssue)
    /// Starting, saving or restoring.
    case busy
    case running
    case paused
}

/// What closing and quitting need from a virtual machine controller.
@MainActor
public protocol VMLifecycleControlling: AnyObject {
    var lifecycleStage: VMLifecycleStage { get }
    var saveEligibility: SavedSessionEligibility { get }

    func waitForPendingOperations() async
    func saveAndStop() async throws
    func retryStopAfterSave() async throws
    func shutDownAndWait() async throws
    func cancelSave()
}

extension VMController: VMLifecycleControlling {
    public var lifecycleStage: VMLifecycleStage {
        switch state {
        case .idle, .stopped, .saved: .notRunning
        case .recoveryRequired(let issue): .recoveryRequired(issue)
        case .starting, .resizingDisk, .saving, .restoring: .busy
        case .running: .running
        case .paused: .paused
        }
    }
}

public enum SessionSaveFailureChoice: Sendable {
    case retry
    case keepOpen
    case shutDown
}

/// What closing a running virtual machine does.
public enum SessionCloseChoice: Equatable, Sendable {
    case saveState
    case shutDown
    /// The window goes away and the virtual machine keeps running without one. Only available when closing a window.
    case keepRunning
}

/// Why a session is being asked to close.
public enum SessionCloseContext: Equatable, Sendable {
    /// The window is being closed. What happens follows the user's preference.
    case window
    /// The user explicitly asked to save the state and close.
    case saveAndClose
    /// The app is quitting. What to do was decided for this virtual machine beforehand, and shutting down
    /// virtual machines that can't be saved has already been confirmed.
    case quit(VMQuitBehavior)

    public var isQuitting: Bool {
        if case .quit = self { true } else { false }
    }
}

/// What came of a request to close a session.
public enum SessionCloseOutcome: Equatable, Sendable {
    /// Nothing changed: the user cancelled, something failed, or the virtual machine is busy. The window stays open.
    case cancelled
    /// The virtual machine isn't running anymore. The window can close and the session can end.
    case stopped
    /// The virtual machine keeps running. The window can close, but the session has to stay around.
    case keptRunning
}

/// The questions that closing a session may need to ask.
@MainActor
public protocol SessionClosePrompting: AnyObject {
    /// What the user prefers to happen when closing this virtual machine.
    var closeBehavior: VMCloseBehavior { get }

    /// Asks whether to save the state, shut down, or keep running. The answer may become the new ``closeBehavior``.
    /// - Returns: `nil` if the user cancelled.
    func chooseCloseAction(context: SessionCloseContext) async -> SessionCloseChoice?
    /// Asks whether to shut down because saving isn't available. The reason is `nil` when saving isn't a concept
    /// that applies to the virtual machine at all, in which case saving must not be mentioned.
    /// Keeping the virtual machine running may be offered as well, but only when a window is being closed.
    /// - Returns: `.shutDown`, `.keepRunning`, or `nil` if the user cancelled.
    func confirmShutDownInsteadOfSaving(reason: String?, context: SessionCloseContext) async -> SessionCloseChoice?
    func presentSaveFailure(_ error: Error, context: SessionCloseContext) async -> SessionSaveFailureChoice
    func confirmShutDown() async -> Bool
    func reportShutDownFailure(_ error: Error)
    /// Called with `true` while the session waits for the guest to shut down.
    func setWaitingForShutdown(_ isWaiting: Bool)
}

// MARK: - Closing One Session

/// Saves a virtual machine (or shuts it down when saving isn't available) so that its window can close or the app can quit,
/// or lets it keep running without a window when that's what the user wants.
///
/// Repeated requests join the one that's in progress. If anything goes wrong, the user decides what happens next,
/// and a failed save is never turned into a force stop.
@MainActor
public final class SessionCloseCoordinator {
    private let controller: VMLifecycleControlling
    private weak var prompts: SessionClosePrompting?

    private var closeTask: Task<SessionCloseOutcome, Never>?

    public init(controller: VMLifecycleControlling, prompts: SessionClosePrompting) {
        self.controller = controller
        self.prompts = prompts
    }

    /// Whether closing involves stopping a virtual machine.
    public var needsStoppingBeforeClose: Bool {
        switch controller.lifecycleStage {
        case .notRunning: false
        case .recoveryRequired(let issue): issue.isStopFailure
        case .busy, .running, .paused: true
        }
    }

    /// Stops waiting for whatever closing is waiting for, including a guest that doesn't shut down. The virtual machine
    /// is left as it is: nothing is forced. A save in progress is asked to stop at its next safe point.
    public func cancelClose() {
        closeTask?.cancel()
        controller.cancelSave()
    }

    public func requestClose(context: SessionCloseContext = .window) async -> SessionCloseOutcome {
        if let closeTask {
            return await closeTask.value
        }

        let task = Task { @MainActor [self] in
            await performClose(context: context)
        }

        closeTask = task

        let result = await task.value

        closeTask = nil

        return result
    }

    private func performClose(context: SessionCloseContext) async -> SessionCloseOutcome {
        guard let prompts else { return .cancelled }

        /// Starting, saving and restoring are never interrupted. Closing waits for them to finish.
        await controller.waitForPendingOperations()

        var chosen: SessionCloseChoice?

        while true {
            switch controller.lifecycleStage {
            case .notRunning:
                return .stopped

            case .recoveryRequired(let issue):
                guard issue.isStopFailure else { return .stopped }

                do {
                    try await controller.retryStopAfterSave()
                    return .stopped
                } catch {
                    guard await shouldRetry(after: error, context: context, prompts: prompts) else { return .cancelled }
                }

            case .busy:
                return .cancelled

            case .running, .paused:
                /// Saving was chosen, but it's not possible anymore: ask again what to do.
                if chosen == .saveState, !controller.saveEligibility.isSupported {
                    chosen = nil
                }

                if chosen == nil {
                    chosen = await resolveCloseAction(context: context, prompts: prompts)
                }

                guard let action = chosen else { return .cancelled }

                switch action {
                case .keepRunning:
                    /// Saving and closing, as well as quitting, always end with the virtual machine stopped.
                    guard context == .window else {
                        logger.fault("Keeping the virtual machine running isn't an option when \(String(describing: context), privacy: .public)")
                        return .cancelled
                    }
                    return .keptRunning

                case .shutDown:
                    return await shutDownAndWait(prompts: prompts) ? .stopped : .cancelled

                case .saveState:
                    do {
                        try await controller.saveAndStop()
                        return .stopped
                    } catch is CancellationError {
                        return .cancelled
                    } catch SavedSessionError.notEligible {
                        /// What's eligible changed since the check above, go through it again.
                        continue
                    } catch {
                        logger.error("Save and stop failed: \(error, privacy: .public)")

                        guard await shouldRetry(after: error, context: context, prompts: prompts) else { return .cancelled }
                    }
                }
            }
        }
    }

    /// Asks what to do about a failed save.
    /// - Returns: `true` to try again, `false` if the virtual machine is to stay open.
    private func shouldRetry(after error: Error, context: SessionCloseContext, prompts: SessionClosePrompting) async -> Bool {
        while true {
            switch await prompts.presentSaveFailure(error, context: context) {
            case .retry:
                return true
            case .keepOpen:
                return false
            case .shutDown:
                /// Declining the confirmation goes back to the choices.
                guard await prompts.confirmShutDown() else { continue }

                /// The user gave up on saving, so this ends the loop either way.
                _ = await shutDownAndWait(prompts: prompts)
                return false
            }
        }
    }

    /// Decides what closing does, asking the user only when the preference calls for it.
    /// - Returns: `nil` if the user cancelled.
    private func resolveCloseAction(context: SessionCloseContext, prompts: SessionClosePrompting) async -> SessionCloseChoice? {
        let eligibility = controller.saveEligibility

        switch context {
        case .quit(let behavior):
            /// Virtual machines that can't be saved were confirmed for shutdown before quitting started.
            return behavior == .saveState && eligibility.isSupported ? .saveState : .shutDown

        case .saveAndClose:
            guard eligibility.isSupported else { return await confirmShutDown(because: eligibility, context: context, prompts: prompts) }
            return .saveState

        case .window:
            let behavior = prompts.closeBehavior

            guard eligibility.isSupported else {
                switch behavior {
                /// Preferences that don't involve saving need no questions, and there's nothing to save anyway.
                case .shutDown: return .shutDown
                case .keepRunning: return .keepRunning
                case .ask, .saveState: return await confirmShutDown(because: eligibility, context: context, prompts: prompts)
                }
            }

            switch behavior {
            case .saveState: return .saveState
            case .shutDown: return .shutDown
            case .keepRunning: return .keepRunning
            case .ask: return await prompts.chooseCloseAction(context: context)
            }
        }
    }

    private func confirmShutDown(because eligibility: SavedSessionEligibility, context: SessionCloseContext, prompts: SessionClosePrompting) async -> SessionCloseChoice? {
        let reason = eligibility.explanationForUser
        return await prompts.confirmShutDownInsteadOfSaving(reason: reason, context: context)
    }

    /// Waits for the guest to shut down, however long that takes.
    private func shutDownAndWait(prompts: SessionClosePrompting) async -> Bool {
        prompts.setWaitingForShutdown(true)
        defer { prompts.setWaitingForShutdown(false) }

        do {
            try await controller.shutDownAndWait()
        } catch is CancellationError {
            logger.info("Stopped waiting for the guest to shut down")
            return false
        } catch {
            logger.error("Shut down failed: \(error, privacy: .public)")
            prompts.reportShutDownFailure(error)
            return false
        }

        return controller.lifecycleStage == .notRunning
    }
}

// MARK: - Quitting

/// One virtual machine that takes part in quitting.
@MainActor
public struct SessionTerminationParticipant {
    public var name: String
    public var controller: VMLifecycleControlling
    public var closer: SessionCloseCoordinator
    /// What quitting does to this virtual machine.
    public var quitBehavior: VMQuitBehavior

    public init(name: String, controller: VMLifecycleControlling, closer: SessionCloseCoordinator, quitBehavior: VMQuitBehavior) {
        self.name = name
        self.controller = controller
        self.closer = closer
        self.quitBehavior = quitBehavior
    }
}

@MainActor
public protocol SessionTerminationPresenting: AnyObject {
    /// Presents the progress of every participant in one place.
    func showProgress(for participants: [SessionTerminationParticipant])
    func dismissProgress()
    /// Asks whether virtual machines that were supposed to be saved but can't be may be shut down so that the app can quit.
    /// A reason is `nil` when saving isn't a concept that applies to the virtual machine, in which case saving must not be mentioned.
    func confirmShutDown(of machines: [(name: String, reason: String?)]) async -> Bool
}

/// Saves or shuts down every active virtual machine before the app quits, following what each one is configured to do.
///
/// This is the only thing that decides whether the app may quit while virtual machines are running. It holds termination
/// for as long as it works, so that the last virtual machine stopping can't be mistaken for permission to quit while
/// another one is still being saved. It always finishes with exactly one answer, and a failure or cancellation means the app keeps running.
@MainActor
public final class SessionTerminationCoordinator {
    private weak var presenter: SessionTerminationPresenting?
    private let holdTermination: @MainActor () -> (@MainActor () -> Void)

    private var task: Task<Bool, Never>?
    private var isCancelled = false
    private var participants = [SessionTerminationParticipant]()

    /// - Parameter holdTermination: Prevents the app from terminating and returns the function that releases it.
    public init(presenter: SessionTerminationPresenting, holdTermination: @escaping @MainActor () -> (@MainActor () -> Void)) {
        self.presenter = presenter
        self.holdTermination = holdTermination
    }

    public var isTerminating: Bool { task != nil }

    /// - Returns: `true` if the app may quit. Requests that arrive while another is in progress join it.
    public func prepareForTermination(participants: [SessionTerminationParticipant]) async -> Bool {
        if let task {
            return await task.value
        }

        let task = Task { @MainActor [self] in
            await perform(participants: participants)
        }

        self.task = task

        let result = await task.value

        self.task = nil

        return result
    }

    /// Stops what's in progress: saves stop at their next safe point, and waiting for a guest to shut down ends right away
    /// (the guest isn't forced to stop). The app keeps running.
    public func cancel() {
        isCancelled = true

        for participant in participants {
            participant.closer.cancelClose()
        }
    }

    private func perform(participants all: [SessionTerminationParticipant]) async -> Bool {
        let active = all.filter(\.closer.needsStoppingBeforeClose)

        guard !active.isEmpty, let presenter else { return true }

        isCancelled = false
        participants = active

        let release = holdTermination()
        presenter.showProgress(for: active)

        defer {
            presenter.dismissProgress()
            release()
            participants = []
        }

        for participant in active {
            await participant.controller.waitForPendingOperations()
        }

        let stillActive = active.filter(\.closer.needsStoppingBeforeClose)

        /// Virtual machines that are supposed to be saved but can't be are shut down instead, which the user confirms before anything is done.
        let unsupported = stillActive.filter { participant in
            let stage = participant.controller.lifecycleStage
            return participant.quitBehavior == .saveState
                && (stage == .running || stage == .paused)
                && !participant.controller.saveEligibility.isSupported
        }

        if !unsupported.isEmpty {
            let reasons = unsupported.map { (name: $0.name, reason: $0.controller.saveEligibility.explanationForUser) }

            guard await presenter.confirmShutDown(of: reasons) else {
                logger.info("Quit cancelled: user declined to shut down virtual machines that can't be saved")
                return false
            }
        }

        /// Saving is done one virtual machine at a time to limit disk pressure.
        for participant in stillActive {
            guard !isCancelled else {
                logger.info("Quit cancelled")
                return false
            }

            guard await participant.closer.requestClose(context: .quit(participant.quitBehavior)) == .stopped else {
                logger.info("Quit cancelled: \(participant.name, privacy: .public) is staying open")
                return false
            }
        }

        return !isCancelled
    }
}
