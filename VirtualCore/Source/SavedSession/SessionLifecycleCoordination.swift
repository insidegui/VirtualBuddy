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
}

/// Why a session is being asked to close.
public enum SessionCloseContext: Equatable, Sendable {
    /// The window is being closed. What happens follows the user's preference.
    case window
    /// The user explicitly asked to save the state and close.
    case saveAndClose
    /// The app is quitting. What to do was decided once for every virtual machine, and shutting down
    /// virtual machines that can't be saved has already been confirmed.
    case quit(SessionCloseChoice)

    public var isQuitting: Bool {
        if case .quit = self { true } else { false }
    }
}

/// The questions that closing a session may need to ask.
@MainActor
public protocol SessionClosePrompting: AnyObject {
    /// What the user prefers to happen when closing a running virtual machine.
    var closeBehavior: VMCloseBehavior { get }

    /// Asks whether to save the state or shut down. The answer may become the new ``closeBehavior``.
    /// - Returns: `nil` if the user cancelled.
    func chooseCloseAction(context: SessionCloseContext) async -> SessionCloseChoice?
    /// Asks whether to shut down because saving isn't available. The reason is `nil` when saving isn't a concept
    /// that applies to the virtual machine at all, in which case saving must not be mentioned.
    func confirmShutDownInsteadOfSaving(reason: String?, context: SessionCloseContext) async -> Bool
    func presentSaveFailure(_ error: Error, context: SessionCloseContext) async -> SessionSaveFailureChoice
    func confirmShutDown() async -> Bool
    func reportShutDownFailure(_ error: Error)
    /// Called with `true` while the session waits for the guest to shut down.
    func setWaitingForShutdown(_ isWaiting: Bool)
}

// MARK: - Closing One Session

/// Saves a virtual machine (or shuts it down when saving isn't available) so that its window can close or the app can quit.
///
/// Repeated requests join the one that's in progress. If anything goes wrong, the user decides what happens next,
/// and a failed save is never turned into a force stop.
@MainActor
public final class SessionCloseCoordinator {
    private let controller: VMLifecycleControlling
    private weak var prompts: SessionClosePrompting?

    private var closeTask: Task<Bool, Never>?

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

    /// - Returns: `true` if the virtual machine isn't running anymore and closing can proceed.
    public func requestClose(context: SessionCloseContext = .window) async -> Bool {
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

    private func performClose(context: SessionCloseContext) async -> Bool {
        guard let prompts else { return false }

        /// Starting, saving and restoring are never interrupted. Closing waits for them to finish.
        await controller.waitForPendingOperations()

        var chosen: SessionCloseChoice?

        while true {
            switch controller.lifecycleStage {
            case .notRunning:
                return true

            case .recoveryRequired(let issue):
                guard issue.isStopFailure else { return true }

                do {
                    try await controller.retryStopAfterSave()
                    return true
                } catch {
                    guard await shouldRetry(after: error, context: context, prompts: prompts) else { return false }
                }

            case .busy:
                return false

            case .running, .paused:
                /// Saving was chosen, but it's not possible anymore: ask again what to do.
                if chosen == .saveState, !controller.saveEligibility.isSupported {
                    chosen = nil
                }

                if chosen == nil {
                    chosen = await resolveCloseAction(context: context, prompts: prompts)
                }

                guard let action = chosen else { return false }

                if action == .shutDown {
                    return await shutDownAndWait(prompts: prompts)
                }

                do {
                    try await controller.saveAndStop()
                    return true
                } catch is CancellationError {
                    return false
                } catch SavedSessionError.notEligible {
                    /// What's eligible changed since the check above, go through it again.
                    continue
                } catch {
                    logger.error("Save and stop failed: \(error, privacy: .public)")

                    guard await shouldRetry(after: error, context: context, prompts: prompts) else { return false }
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
        case .quit(let choice):
            /// Virtual machines that can't be saved were confirmed for shutdown before quitting started.
            return choice == .saveState && eligibility.isSupported ? .saveState : .shutDown

        case .saveAndClose:
            guard eligibility.isSupported else { return await confirmShutDown(because: eligibility, context: context, prompts: prompts) }
            return .saveState

        case .window:
            guard eligibility.isSupported else {
                /// A preference to shut down needs no questions, and there's nothing to save anyway.
                if prompts.closeBehavior == .shutDown { return .shutDown }
                return await confirmShutDown(because: eligibility, context: context, prompts: prompts)
            }

            switch prompts.closeBehavior {
            case .saveState: return .saveState
            case .shutDown: return .shutDown
            case .ask: return await prompts.chooseCloseAction(context: context)
            }
        }
    }

    private func confirmShutDown(because eligibility: SavedSessionEligibility, context: SessionCloseContext, prompts: SessionClosePrompting) async -> SessionCloseChoice? {
        let reason = eligibility.explanationForUser
        return await prompts.confirmShutDownInsteadOfSaving(reason: reason, context: context) ? .shutDown : nil
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

    public init(name: String, controller: VMLifecycleControlling, closer: SessionCloseCoordinator) {
        self.name = name
        self.controller = controller
        self.closer = closer
    }
}

@MainActor
public protocol SessionTerminationPresenting: AnyObject {
    /// Presents the progress of every participant in one place.
    func showProgress(for participants: [SessionTerminationParticipant])
    func dismissProgress()
    /// What the user prefers to happen when closing a running virtual machine.
    var closeBehavior: VMCloseBehavior { get }
    /// Asks whether to save the state or shut down, for every virtual machine that's running. The answer may become the new ``closeBehavior``.
    /// - Returns: `nil` if the user cancelled.
    func chooseCloseAction() async -> SessionCloseChoice?
    /// Asks whether virtual machines that can't be saved may be shut down so that the app can quit.
    /// A reason is `nil` when saving isn't a concept that applies to the virtual machine, in which case saving must not be mentioned.
    func confirmShutDown(of machines: [(name: String, reason: String?)]) async -> Bool
}

/// Saves or shuts down every active virtual machine before the app quits.
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

        let unsupported = stillActive.filter { participant in
            let stage = participant.controller.lifecycleStage
            return (stage == .running || stage == .paused) && !participant.controller.saveEligibility.isSupported
        }
        let saveable = stillActive.filter { participant in !unsupported.contains { $0.controller === participant.controller } }

        func confirmUnsupported() async -> Bool {
            guard !unsupported.isEmpty else { return true }

            let reasons = unsupported.map { (name: $0.name, reason: $0.controller.saveEligibility.explanationForUser) }

            guard await presenter.confirmShutDown(of: reasons) else {
                logger.info("Quit cancelled: user declined to shut down virtual machines that can't be saved")
                return false
            }
            return true
        }

        /// What to do is decided once, for every virtual machine.
        let canSave = saveable.contains { participant in
            let stage = participant.controller.lifecycleStage
            return (stage == .running || stage == .paused) && participant.controller.saveEligibility.isSupported
        }

        let choice: SessionCloseChoice

        switch presenter.closeBehavior {
        case .shutDown:
            choice = .shutDown
        case .saveState:
            guard await confirmUnsupported() else { return false }
            choice = .saveState
        case .ask:
            if canSave {
                guard let answer = await presenter.chooseCloseAction() else {
                    logger.info("Quit cancelled: user cancelled the choice between saving and shutting down")
                    return false
                }
                if answer == .saveState {
                    guard await confirmUnsupported() else { return false }
                }
                choice = answer
            } else {
                guard await confirmUnsupported() else { return false }
                choice = .shutDown
            }
        }

        /// Saving is done one virtual machine at a time to limit disk pressure.
        for participant in saveable + unsupported {
            guard !isCancelled else {
                logger.info("Quit cancelled")
                return false
            }

            guard await participant.closer.requestClose(context: .quit(choice)) else {
                logger.info("Quit cancelled: \(participant.name, privacy: .public) is staying open")
                return false
            }
        }

        return !isCancelled
    }
}
