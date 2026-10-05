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

/// Why a session is being asked to close.
public enum SessionCloseContext: Equatable, Sendable {
    case window
    /// The app is quitting. When `shutdownConfirmed` is `true`, shutting down virtual machines that can't be saved has already been confirmed.
    case quit(shutdownConfirmed: Bool)

    public var isQuitting: Bool {
        if case .quit = self { true } else { false }
    }
}

/// The questions that closing a session may need to ask.
@MainActor
public protocol SessionClosePrompting: AnyObject {
    var hasAcknowledgedIntroduction: Bool { get }

    func confirmIntroduction(context: SessionCloseContext) async -> Bool
    func confirmShutDownInsteadOfSaving(reason: String, context: SessionCloseContext) async -> Bool
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
                guard controller.saveEligibility.isSupported else {
                    return await shutDownInsteadOfSaving(context: context, prompts: prompts)
                }

                if !prompts.hasAcknowledgedIntroduction {
                    guard await prompts.confirmIntroduction(context: context) else { return false }
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

    private func shutDownInsteadOfSaving(context: SessionCloseContext, prompts: SessionClosePrompting) async -> Bool {
        if case .quit(shutdownConfirmed: true) = context {
            return await shutDownAndWait(prompts: prompts)
        }

        let reason = controller.saveEligibility.primaryIssue?.explanation ?? "Saving isn’t available for this virtual machine."

        guard await prompts.confirmShutDownInsteadOfSaving(reason: reason, context: context) else { return false }

        return await shutDownAndWait(prompts: prompts)
    }

    /// Waits for the guest to shut down, however long that takes.
    private func shutDownAndWait(prompts: SessionClosePrompting) async -> Bool {
        prompts.setWaitingForShutdown(true)
        defer { prompts.setWaitingForShutdown(false) }

        do {
            try await controller.shutDownAndWait()
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
    /// Asks whether virtual machines that can't be saved may be shut down so that the app can quit.
    func confirmShutDown(of machines: [(name: String, reason: String)]) async -> Bool
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

    /// Stops what's in progress. Takes effect once the virtual machine that's being saved reaches a safe point.
    public func cancel() {
        isCancelled = true

        for participant in participants {
            participant.controller.cancelSave()
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

        if !unsupported.isEmpty {
            let reasons = unsupported.map {
                (name: $0.name, reason: $0.controller.saveEligibility.primaryIssue?.explanation ?? "Saving isn’t available for this virtual machine.")
            }

            guard await presenter.confirmShutDown(of: reasons) else {
                logger.info("Quit cancelled: user declined to shut down virtual machines that can't be saved")
                return false
            }
        }

        /// Saving is done one virtual machine at a time to limit disk pressure.
        for participant in saveable + unsupported {
            guard !isCancelled else {
                logger.info("Quit cancelled")
                return false
            }

            guard await participant.closer.requestClose(context: .quit(shutdownConfirmed: true)) else {
                logger.info("Quit cancelled: \(participant.name, privacy: .public) is staying open")
                return false
            }
        }

        return !isCancelled
    }
}
