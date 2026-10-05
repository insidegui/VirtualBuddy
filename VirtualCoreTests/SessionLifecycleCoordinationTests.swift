import Testing
import Foundation
@testable import VirtualCore

// MARK: - Fakes

@MainActor
private final class FakeController: VMLifecycleControlling {
    var lifecycleStage: VMLifecycleStage
    var saveEligibility = SavedSessionEligibility.supported

    /// Consumed by each call to `saveAndStop`. When empty, saving succeeds.
    var saveOutcomes = [Error?]()
    var retryStopOutcomes = [Error?]()
    var shutDownError: Error?
    /// A guest that never finishes shutting down. Only cancelling ends the wait.
    var shutDownHangs = false
    /// What becomes of the eligibility when saving fails because it changed.
    var eligibilityAfterNotEligible: SavedSessionEligibility?

    private(set) var saveCalls = 0
    private(set) var retryStopCalls = 0
    private(set) var shutDownCalls = 0
    private(set) var cancelSaveCalls = 0

    /// Holds `saveAndStop` open until the test releases it.
    var saveGate: AsyncGate?
    var pendingOperationsGate: AsyncGate?

    let name: String

    init(name: String, running: Bool = true) {
        self.name = name
        self.lifecycleStage = running ? .running : .notRunning
    }

    func waitForPendingOperations() async { await pendingOperationsGate?.wait() }

    func saveAndStop() async throws {
        saveCalls += 1
        await saveGate?.wait()
        if !saveOutcomes.isEmpty, let error = saveOutcomes.removeFirst() {
            if case SavedSessionError.notEligible = error, let eligibilityAfterNotEligible { saveEligibility = eligibilityAfterNotEligible }
            throw error
        }
        lifecycleStage = .notRunning
    }

    func retryStopAfterSave() async throws {
        retryStopCalls += 1
        if !retryStopOutcomes.isEmpty, let error = retryStopOutcomes.removeFirst() { throw error }
        lifecycleStage = .notRunning
    }

    func shutDownAndWait() async throws {
        shutDownCalls += 1
        if shutDownHangs {
            while !Task.isCancelled { await Task.yield() }
            throw CancellationError()
        }
        if let shutDownError { throw shutDownError }
        lifecycleStage = .notRunning
    }

    func cancelSave() { cancelSaveCalls += 1 }
}

/// A one-shot gate that suspends waiters until it's opened.
@MainActor
private final class AsyncGate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
private final class FakePrompts: SessionClosePrompting {
    var closeBehavior = VMCloseBehavior.saveState
    var chooseAnswer: SessionCloseChoice? = .saveState
    var shutDownInsteadAnswer = true
    var failureChoices = [SessionSaveFailureChoice]()
    var shutDownConfirmations = [Bool]()

    private(set) var chooseCount = 0
    private(set) var shutDownInsteadCount = 0
    private(set) var shutDownInsteadReasons = [String?]()
    private(set) var failureCount = 0
    private(set) var shutDownConfirmationCount = 0
    private(set) var waitingValues = [Bool]()

    func chooseCloseAction(context: SessionCloseContext) async -> SessionCloseChoice? {
        chooseCount += 1
        return chooseAnswer
    }

    func confirmShutDownInsteadOfSaving(reason: String?, context: SessionCloseContext) async -> Bool {
        shutDownInsteadCount += 1
        shutDownInsteadReasons.append(reason)
        return shutDownInsteadAnswer
    }

    func presentSaveFailure(_ error: Error, context: SessionCloseContext) async -> SessionSaveFailureChoice {
        failureCount += 1
        return failureChoices.isEmpty ? .keepOpen : failureChoices.removeFirst()
    }

    func confirmShutDown() async -> Bool {
        shutDownConfirmationCount += 1
        return shutDownConfirmations.isEmpty ? true : shutDownConfirmations.removeFirst()
    }

    func reportShutDownFailure(_ error: Error) {}

    func setWaitingForShutdown(_ isWaiting: Bool) { waitingValues.append(isWaiting) }
}

@MainActor
private final class FakePresenter: SessionTerminationPresenting {
    var shutDownAnswer = true
    var closeBehavior = VMCloseBehavior.saveState
    var chooseAnswer: SessionCloseChoice? = .saveState
    private(set) var chooseCount = 0
    private(set) var shownCount = 0
    private(set) var dismissedCount = 0
    private(set) var confirmedMachines = [[String]]()

    func showProgress(for participants: [SessionTerminationParticipant]) { shownCount += 1 }
    func dismissProgress() { dismissedCount += 1 }

    func chooseCloseAction() async -> SessionCloseChoice? {
        chooseCount += 1
        return chooseAnswer
    }

    func confirmShutDown(of machines: [(name: String, reason: String?)]) async -> Bool {
        confirmedMachines.append(machines.map(\.name))
        return shutDownAnswer
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "boom" }
}

// MARK: - Closing

@MainActor
final class SessionCloseCoordinatorTests {
    private func makeCloser(_ controller: FakeController, _ prompts: FakePrompts) -> SessionCloseCoordinator {
        SessionCloseCoordinator(controller: controller, prompts: prompts)
    }

    @Test func closingAVirtualMachineThatIsNotRunningNeedsNothing() async {
        for stage in [VMLifecycleStage.notRunning, .recoveryRequired(.interruptedAfterResume)] {
            let controller = FakeController(name: "A", running: false)
            controller.lifecycleStage = stage
            let prompts = FakePrompts()

            let closed = await makeCloser(controller, prompts).requestClose()

            #expect(closed)
            #expect(controller.saveCalls == 0)
            #expect(prompts.failureCount == 0)
        }
    }

    @Test func closingSavesAndNeverShutsDown() async {
        let controller = FakeController(name: "A")
        let prompts = FakePrompts()

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(controller.saveCalls == 1)
        #expect(controller.shutDownCalls == 0)
        #expect(prompts.chooseCount == 0)
    }

    @Test func askingEveryTimeOffersSaveStateOrShutdownAndCancelKeepsWindowOpen() async {
        let controller = FakeController(name: "A")
        let prompts = FakePrompts()
        prompts.closeBehavior = .ask
        prompts.chooseAnswer = nil

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(!closed)
        #expect(prompts.chooseCount == 1)
        #expect(controller.saveCalls == 0)
        #expect(controller.shutDownCalls == 0)
    }

    @Test func askingEveryTimeAndChoosingSaveSaves() async {
        let controller = FakeController(name: "A")
        let prompts = FakePrompts()
        prompts.closeBehavior = .ask
        prompts.chooseAnswer = .saveState

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(controller.saveCalls == 1)
        #expect(controller.shutDownCalls == 0)
    }

    @Test func askingEveryTimeAndChoosingShutdownShutsDownWithoutSaving() async {
        let controller = FakeController(name: "A")
        let prompts = FakePrompts()
        prompts.closeBehavior = .ask
        prompts.chooseAnswer = .shutDown

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(controller.saveCalls == 0)
        #expect(controller.shutDownCalls == 1)
    }

    @Test func preferenceToSaveNeverAsks() async {
        let controller = FakeController(name: "A")
        let prompts = FakePrompts()
        prompts.closeBehavior = .saveState

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(prompts.chooseCount == 0)
        #expect(controller.saveCalls == 1)
    }

    @Test func preferenceToShutDownNeverAsksAndNeverSaves() async {
        let controller = FakeController(name: "A")
        let prompts = FakePrompts()
        prompts.closeBehavior = .shutDown

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(prompts.chooseCount == 0)
        #expect(prompts.shutDownInsteadCount == 0)
        #expect(controller.saveCalls == 0)
        #expect(controller.shutDownCalls == 1)
    }

    @Test func explicitSaveAndCloseIgnoresThePreference() async {
        let controller = FakeController(name: "A")
        let prompts = FakePrompts()
        prompts.closeBehavior = .shutDown

        let closed = await makeCloser(controller, prompts).requestClose(context: .saveAndClose)

        #expect(closed)
        #expect(controller.saveCalls == 1)
        #expect(controller.shutDownCalls == 0)
    }

    @Test func virtualMachinesThatCannotSaveAtAllGetAPlainShutdownQuestionWithoutMentioningSaving() async {
        for behavior in [VMCloseBehavior.ask, .saveState] {
            let controller = FakeController(name: "Linux")
            controller.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])
            let prompts = FakePrompts()
            prompts.closeBehavior = behavior

            let closed = await makeCloser(controller, prompts).requestClose()

            #expect(closed)
            #expect(prompts.chooseCount == 0, "there's no choice to offer")
            #expect(prompts.shutDownInsteadReasons.count == 1)
            #expect(prompts.shutDownInsteadReasons.first == .some(nil), "no reason means saving must not be mentioned")
            #expect(controller.shutDownCalls == 1)
        }
    }

    @Test func plainShutdownQuestionCanBeCancelled() async {
        let controller = FakeController(name: "Linux")
        controller.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])
        let prompts = FakePrompts()
        prompts.shutDownInsteadAnswer = false

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(!closed)
        #expect(controller.shutDownCalls == 0)
    }

    @Test func otherReasonsForNotSavingAreExplained() async {
        let controller = FakeController(name: "Mac")
        controller.saveEligibility = SavedSessionEligibility(issues: [.usbDeviceAttached])
        let prompts = FakePrompts()

        _ = await makeCloser(controller, prompts).requestClose()

        #expect(prompts.shutDownInsteadReasons.first??.isEmpty == false)
    }

    @Test func repeatedCloseRequestsJoinTheOneInProgress() async {
        let controller = FakeController(name: "A")
        controller.saveGate = AsyncGate()
        let prompts = FakePrompts()
        let closer = makeCloser(controller, prompts)

        let first = Task { await closer.requestClose() }
        let second = Task { await closer.requestClose() }
        let third = Task { await closer.requestClose(context: .quit(.saveState)) }

        for _ in 0..<5 { await Task.yield() }
        controller.saveGate?.open()

        let results = [await first.value, await second.value, await third.value]

        #expect(results == [true, true, true])
        #expect(controller.saveCalls == 1, "only one save may happen")
        withExtendedLifetime(prompts) { }
    }

    @Test func closingWaitsForOperationsInProgressBeforeLookingAtTheState() async {
        let controller = FakeController(name: "A", running: false)
        controller.lifecycleStage = .busy
        controller.pendingOperationsGate = AsyncGate()
        let prompts = FakePrompts()
        let closer = makeCloser(controller, prompts)

        let closing = Task { await closer.requestClose() }
        await Task.yield()
        await Task.yield()

        #expect(controller.saveCalls == 0, "nothing may happen while the virtual machine is still starting")

        controller.lifecycleStage = .running
        controller.pendingOperationsGate?.open()

        let closed = await closing.value
        #expect(closed)
        #expect(controller.saveCalls == 1)
        withExtendedLifetime(prompts) { }
    }

    @Test func failedSaveKeepsWindowOpenWithoutShuttingDown() async {
        let controller = FakeController(name: "A")
        controller.saveOutcomes = [TestFailure()]
        let prompts = FakePrompts()
        prompts.failureChoices = [.keepOpen]

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(!(closed))
        #expect(prompts.failureCount == 1)
        #expect(controller.shutDownCalls == 0, "a failed save is never silently replaced by a shutdown")
        #expect(controller.lifecycleStage == .running)
    }

    @Test func retryAfterFailedSaveSavesAgain() async {
        let controller = FakeController(name: "A")
        controller.saveOutcomes = [TestFailure(), nil]
        let prompts = FakePrompts()
        prompts.failureChoices = [.retry]

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(controller.saveCalls == 2)
        #expect(controller.shutDownCalls == 0)
    }

    @Test func shutDownAfterFailedSaveRequiresConfirmationAndWaitsForTheGuest() async {
        let controller = FakeController(name: "A")
        controller.saveOutcomes = [TestFailure()]
        let prompts = FakePrompts()
        prompts.failureChoices = [.shutDown, .shutDown]
        prompts.shutDownConfirmations = [false, true]

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(!(closed), "the window stays open after the user gave up on saving, the caller closes it when the guest is down")
        #expect(prompts.failureCount == 2, "declining the confirmation goes back to the choices")
        #expect(prompts.shutDownConfirmationCount == 2)
        #expect(controller.shutDownCalls == 1)
        #expect(prompts.waitingValues == [true, false])
        #expect(controller.lifecycleStage == .notRunning)
    }

    @Test func unsupportedVirtualMachineIsShutDownAfterConfirmation() async {
        let controller = FakeController(name: "A")
        controller.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])
        let prompts = FakePrompts()

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(prompts.shutDownInsteadCount == 1)
        #expect(controller.saveCalls == 0)
        #expect(controller.shutDownCalls == 1)
    }

    @Test func decliningToShutDownUnsupportedVirtualMachineKeepsItRunning() async {
        let controller = FakeController(name: "A")
        controller.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])
        let prompts = FakePrompts()
        prompts.shutDownInsteadAnswer = false

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(!(closed))
        #expect(controller.shutDownCalls == 0)
        #expect(controller.lifecycleStage == .running)
    }

    @Test func slowShutdownIsWaitedForNotForced() async {
        let controller = FakeController(name: "A")
        controller.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])
        controller.shutDownError = TestFailure()
        let prompts = FakePrompts()

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(!(closed), "if the shutdown can't be waited for, nothing else is done to the virtual machine")
        #expect(controller.lifecycleStage == .running)
    }

    @Test func stopFailureAfterSaveIsRetriedInsteadOfSavingAgain() async {
        let controller = FakeController(name: "A", running: false)
        controller.lifecycleStage = .recoveryRequired(.stopFailedAfterSave("busy"))
        controller.retryStopOutcomes = [TestFailure(), nil]
        let prompts = FakePrompts()
        prompts.failureChoices = [.retry]

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(controller.retryStopCalls == 2)
        #expect(controller.saveCalls == 0, "a session that's already saved must not be saved again")
    }

    @Test func eligibilityChangeDuringSaveIsReevaluated() async {
        let controller = FakeController(name: "A")
        controller.saveOutcomes = [SavedSessionError.notEligible(.usbDeviceAttached)]
        controller.eligibilityAfterNotEligible = SavedSessionEligibility(issues: [.usbDeviceAttached])
        let prompts = FakePrompts()

        let closed = await makeCloser(controller, prompts).requestClose()

        #expect(closed)
        #expect(controller.saveCalls == 1)
        #expect(controller.shutDownCalls == 1, "once saving is known to be unavailable, the virtual machine is shut down instead")
        #expect(prompts.shutDownInsteadCount == 1)
    }
}

// MARK: - Quitting

@MainActor
final class SessionTerminationCoordinatorTests {
    private final class Hold {
        var holds = 0
        var releases = 0
    }

    private func makeCoordinator(presenter: FakePresenter, hold: Hold) -> SessionTerminationCoordinator {
        SessionTerminationCoordinator(presenter: presenter) {
            hold.holds += 1
            return { hold.releases += 1 }
        }
    }

    /// The prompts are returned too because the closer only holds them weakly.
    private var retainedPrompts = [FakePrompts]()

    private func participant(_ controller: FakeController) -> (SessionTerminationParticipant, FakePrompts) {
        let prompts = FakePrompts()
        retainedPrompts.append(prompts)
        return (SessionTerminationParticipant(name: controller.name, controller: controller, closer: SessionCloseCoordinator(controller: controller, prompts: prompts)), prompts)
    }

    @Test func quittingWithoutActiveVirtualMachinesDoesNotHoldTermination() async {
        let hold = Hold()
        let presenter = FakePresenter()
        let idle = FakeController(name: "A", running: false)

        let result = await makeCoordinator(presenter: presenter, hold: hold).prepareForTermination(participants: [participant(idle).0])

        #expect(result)
        #expect(hold.holds == 0)
        #expect(presenter.shownCount == 0)
    }

    @Test func quittingSavesEveryActiveVirtualMachineSequentiallyAndHoldsTerminationThroughout() async {
        let hold = Hold()
        let presenter = FakePresenter()
        let a = FakeController(name: "A")
        let b = FakeController(name: "B")

        let result = await makeCoordinator(presenter: presenter, hold: hold)
            .prepareForTermination(participants: [participant(a).0, participant(b).0])

        #expect(result)
        #expect(a.saveCalls == 1 && b.saveCalls == 1)
        #expect(hold.holds == 1)
        #expect(hold.releases == 1, "termination is held exactly once and released exactly once")
        #expect(presenter.shownCount == 1, "one progress presentation for every virtual machine")
        #expect(presenter.dismissedCount == 1)
    }

    @Test func savingStopsAtTheFirstVirtualMachineThatStaysOpenAndQuittingIsCancelled() async {
        let hold = Hold()
        let presenter = FakePresenter()
        let a = FakeController(name: "A")
        a.saveOutcomes = [TestFailure()]
        let b = FakeController(name: "B")
        let (pa, promptsA) = participant(a)
        promptsA.failureChoices = [.keepOpen]

        let result = await makeCoordinator(presenter: presenter, hold: hold).prepareForTermination(participants: [pa, participant(b).0])

        #expect(!(result))
        #expect(b.saveCalls == 0, "nothing else is touched after the user chose to keep a virtual machine open")
        #expect(a.shutDownCalls == 0)
        #expect(hold.releases == 1, "cancelling must release the hold")
        #expect(presenter.dismissedCount == 1)
    }

    @Test func mixedSupportedAndUnsupportedAskOnceBeforeAnythingIsDone() async {
        let hold = Hold()
        let presenter = FakePresenter()
        let supported = FakeController(name: "Supported")
        let unsupported = FakeController(name: "Unsupported")
        unsupported.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])

        let result = await makeCoordinator(presenter: presenter, hold: hold)
            .prepareForTermination(participants: [participant(supported).0, participant(unsupported).0])

        #expect(result)
        #expect(presenter.confirmedMachines == [["Unsupported"] as [String]])
        #expect(supported.saveCalls == 1)
        #expect(supported.shutDownCalls == 0)
        #expect(unsupported.saveCalls == 0)
        #expect(unsupported.shutDownCalls == 1)
    }

    @Test func decliningToShutDownUnsupportedMachinesCancelsBeforeSavingAnything() async {
        let hold = Hold()
        let presenter = FakePresenter()
        presenter.shutDownAnswer = false
        let supported = FakeController(name: "Supported")
        let unsupported = FakeController(name: "Unsupported")
        unsupported.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])

        let result = await makeCoordinator(presenter: presenter, hold: hold)
            .prepareForTermination(participants: [participant(supported).0, participant(unsupported).0])

        #expect(!(result))
        #expect(supported.saveCalls == 0)
        #expect(unsupported.shutDownCalls == 0)
        #expect(hold.releases == 1)
    }

    @Test func cancellationStopsQueuedWorkAndAsksTheSaveInProgressToStop() async {
        let hold = Hold()
        let presenter = FakePresenter()
        let a = FakeController(name: "A")
        a.saveGate = AsyncGate()
        let b = FakeController(name: "B")
        let coordinator = makeCoordinator(presenter: presenter, hold: hold)

        let quitting = Task { await coordinator.prepareForTermination(participants: [participant(a).0, participant(b).0]) }
        for _ in 0..<5 { await Task.yield() }

        coordinator.cancel()
        a.saveGate?.open()

        let result = await quitting.value

        #expect(!(result))
        #expect(a.cancelSaveCalls == 1)
        #expect(b.saveCalls == 0, "queued work must not start after cancellation")
        #expect(hold.releases == 1)
    }

    @Test func repeatedQuitRequestsJoinTheOneInProgress() async {
        let hold = Hold()
        let presenter = FakePresenter()
        let a = FakeController(name: "A")
        a.saveGate = AsyncGate()
        let coordinator = makeCoordinator(presenter: presenter, hold: hold)
        let participants = [participant(a).0]

        let first = Task { await coordinator.prepareForTermination(participants: participants) }
        for _ in 0..<3 { await Task.yield() }
        let second = Task { await coordinator.prepareForTermination(participants: participants) }
        for _ in 0..<3 { await Task.yield() }

        #expect(coordinator.isTerminating)

        a.saveGate?.open()

        let results = await [first.value, second.value]

        #expect(results == [true, true])
        #expect(a.saveCalls == 1)
        #expect(hold.holds == 1)
        #expect(!(coordinator.isTerminating), "state must be reset so that the next attempt starts over")
    }

    @Test func nextQuitAttemptStartsOverAfterCancellation() async {
        let hold = Hold()
        let presenter = FakePresenter()
        let a = FakeController(name: "A")
        a.saveOutcomes = [TestFailure(), nil]
        let (pa, prompts) = participant(a)
        prompts.failureChoices = [.keepOpen]
        let coordinator = makeCoordinator(presenter: presenter, hold: hold)

        let first = await coordinator.prepareForTermination(participants: [pa])
        let second = await coordinator.prepareForTermination(participants: [pa])

        #expect(!(first))
        #expect(second)
        #expect(hold.holds == 2)
        #expect(hold.releases == 2)
    }

    private func askedParticipant(_ controller: FakeController) -> SessionTerminationParticipant {
        let prompts = FakePrompts()
        prompts.closeBehavior = .ask
        retainedPrompts.append(prompts)
        return SessionTerminationParticipant(name: controller.name, controller: controller, closer: SessionCloseCoordinator(controller: controller, prompts: prompts))
    }

    @Test func quittingWhenAskingAsksOnceForEveryVirtualMachine() async {
        let hold = Hold()
        let presenter = FakePresenter()
        presenter.closeBehavior = .ask
        presenter.chooseAnswer = .shutDown
        let a = FakeController(name: "A")
        let b = FakeController(name: "B")

        let result = await makeCoordinator(presenter: presenter, hold: hold)
            .prepareForTermination(participants: [askedParticipant(a), askedParticipant(b)])

        #expect(result)
        #expect(presenter.chooseCount == 1)
        #expect(a.saveCalls == 0 && b.saveCalls == 0)
        #expect(a.shutDownCalls == 1 && b.shutDownCalls == 1)
    }

    @Test func quittingWhenAskingAndCancellingKeepsEverythingRunning() async {
        let hold = Hold()
        let presenter = FakePresenter()
        presenter.closeBehavior = .ask
        presenter.chooseAnswer = nil
        let a = FakeController(name: "A")

        let result = await makeCoordinator(presenter: presenter, hold: hold).prepareForTermination(participants: [askedParticipant(a)])

        #expect(!result)
        #expect(a.saveCalls == 0 && a.shutDownCalls == 0)
        #expect(hold.releases == 1)
    }

    @Test func quittingWithPreferenceToShutDownNeverAsksOrConfirms() async {
        let hold = Hold()
        let presenter = FakePresenter()
        presenter.closeBehavior = .shutDown
        let mac = FakeController(name: "Mac")
        let linux = FakeController(name: "Linux")
        linux.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])

        let result = await makeCoordinator(presenter: presenter, hold: hold)
            .prepareForTermination(participants: [participant(mac).0, participant(linux).0])

        #expect(result)
        #expect(presenter.chooseCount == 0)
        #expect(presenter.confirmedMachines.isEmpty)
        #expect(mac.saveCalls == 0 && mac.shutDownCalls == 1 && linux.shutDownCalls == 1)
    }

    @Test func quittingWithOnlyVirtualMachinesThatCannotSaveJustConfirmsShutdown() async {
        let hold = Hold()
        let presenter = FakePresenter()
        presenter.closeBehavior = .ask
        let linux = FakeController(name: "Linux")
        linux.saveEligibility = SavedSessionEligibility(issues: [.unsupportedGuest])

        let result = await makeCoordinator(presenter: presenter, hold: hold).prepareForTermination(participants: [askedParticipant(linux)])

        #expect(result)
        #expect(presenter.chooseCount == 0, "there's nothing to choose between")
        #expect(presenter.confirmedMachines == [["Linux"] as [String]])
        #expect(linux.shutDownCalls == 1)
    }

    @Test func cancellingEndsTheWaitForAGuestThatRefusesToShutDown() async {
        let hold = Hold()
        let presenter = FakePresenter()
        presenter.closeBehavior = .shutDown
        let stubborn = FakeController(name: "Stubborn")
        stubborn.shutDownHangs = true
        let coordinator = makeCoordinator(presenter: presenter, hold: hold)

        let quitting = Task { await coordinator.prepareForTermination(participants: [participant(stubborn).0]) }
        for _ in 0..<10 { await Task.yield() }

        #expect(coordinator.isTerminating)
        #expect(stubborn.shutDownCalls == 1)

        coordinator.cancel()

        let result = await quitting.value

        #expect(!result, "quitting must be cancelled, not forced")
        #expect(stubborn.lifecycleStage == .running, "the guest is left alone")
        #expect(presenter.dismissedCount == 1)
        #expect(hold.releases == 1)
        #expect(!coordinator.isTerminating)
    }
}
