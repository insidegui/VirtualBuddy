import Testing
import Foundation
import Combine
import Virtualization
@testable import VirtualCore

@MainActor
final class VMControllerSavedSessionTests {
    private let directoryURL: URL
    private let diskContents = Data("disk".utf8)

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "VMControllerSavedSessionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    // MARK: Helpers

    private func makeVirtualMachine() throws -> VBVirtualMachine {
        var model = try VBVirtualMachine(
            bundleURL: directoryURL.appending(path: "Test.\(VBVirtualMachine.bundleExtension)", directoryHint: .isDirectory),
            isNewInstall: true
        )
        model.metadata.installFinished = true
        try model.saveMetadata()

        try diskContents.write(to: model.bundleURL.appending(path: "Disk.img"))
        try Data("aux".utf8).write(to: model.auxiliaryStorageURL)
        try Data("machine identifier".utf8).write(to: model.machineIdentifierURL)
        try Data("hardware model".utf8).write(to: model.hardwareModelURL)

        return model
    }

    private func saveSession(in model: VBVirtualMachine) throws {
        let storage = SavedSessionStorage(bundleURL: model.bundleURL)

        let plan = SavedSessionCapturePlan(
            resources: [
                .init(id: "disk", role: .disk, sourceURL: model.bundleURL.appending(path: "Disk.img"), workingPath: "Disk.img"),
                .init(id: "aux", role: .auxiliaryStorage, sourceURL: model.auxiliaryStorageURL, workingPath: "AuxiliaryStorage"),
                .init(id: "mid", role: .machineIdentifier, sourceURL: model.machineIdentifierURL, workingPath: "MachineIdentifier"),
                .init(id: "hw", role: .hardwareModel, sourceURL: model.hardwareModelURL, workingPath: "HardwareModel")
            ],
            configuration: model.configuration,
            runtimeDescription: .init(configuration: .init()),
            screenshotSourceURL: nil,
            wasPausedBeforeSave: false,
            memorySize: 1
        )

        let staged = try storage.stageCapture(plan)
        try Data("state".utf8).write(to: staged.stateFileURL)
        try storage.publish(staged)
    }

    private func makeController(for model: VBVirtualMachine, options: VMSessionOptions? = nil) throws -> VMController {
        VMController(with: try VBVirtualMachine(bundleURL: model.bundleURL, isNewInstall: false, createIfNeeded: false), library: .preview, options: options)
    }

    // MARK: Resting State

    @Test func controllerForVirtualMachineWithoutSessionIsIdle() throws {
        let controller = try makeController(for: try makeVirtualMachine())

        #expect(controller.state.isIdle)
        #expect(controller.savedSession == nil)
        #expect(controller.canStart)
    }

    @Test func controllerForSavedVirtualMachineIsSaved() throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)

        let controller = try makeController(for: model)

        #expect(controller.state.isSaved)
        #expect(controller.savedSession?.isReady == true)
        #expect(controller.canStart, "starting a saved virtual machine resumes it")
    }

    @Test func controllerForInterruptedSessionRequiresRecovery() throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let storage = SavedSessionStorage(bundleURL: model.bundleURL)
        try storage.markConsumed(try storage.prepareRestore())

        let controller = try makeController(for: model)

        guard case .recoveryRequired(.interruptedAfterResume) = controller.state else {
            Issue.record("expected recovery to be required, got \(controller.state)")
            return
        }
    }

    // MARK: Starting

    @Test func specialBootModesCannotBypassTheDiscardConfirmation() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)

        for options in [VMSessionOptions(bootInRecoveryMode: true), VMSessionOptions(bootInDFUMode: true), VMSessionOptions(bootOnInstallDevice: true)] {
            let controller = try makeController(for: model, options: options)
            guard controller.options.requestsSpecialBoot else { continue }

            await #expect(throws: SavedSessionError.self) {
                try await controller.start()
            }

            #expect(controller.state.isSaved, "the saved session must be left alone")
            #expect(SavedSessionStorage(bundleURL: model.bundleURL).inspect()?.status == .ready)
        }
    }

    @Test func startingWhileRecoveryIsRequiredAsksForRecoveryInsteadOfBooting() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let storage = SavedSessionStorage(bundleURL: model.bundleURL)
        try storage.markConsumed(try storage.prepareRestore())
        try Data("newer".utf8).write(to: model.bundleURL.appending(path: "Disk.img"))

        let controller = try makeController(for: model)

        await #expect(throws: SavedSessionError.self) {
            try await controller.start()
        }

        guard case .recoveryRequired = controller.state else {
            Issue.record("expected recovery to be required, got \(controller.state)")
            return
        }
        #expect(try Data(contentsOf: model.bundleURL.appending(path: "Disk.img")) == Data("newer".utf8), "newer disks must never be replaced")
    }

    // MARK: Discarding and Recovering

    @Test func discardingKeepsTheDisksAndLeavesNoSession() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let controller = try makeController(for: model)

        try await controller.discardSavedSession()

        #expect(controller.state.isIdle)
        #expect(controller.savedSession == nil)
        #expect(try Data(contentsOf: model.bundleURL.appending(path: "Disk.img")) == diskContents)
        #expect(SavedSessionStorage(bundleURL: model.bundleURL).inspect() == nil)
    }

    @Test func reinstatingAnInterruptedSessionMakesItResumableAgain() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let storage = SavedSessionStorage(bundleURL: model.bundleURL)
        try storage.markConsumed(try storage.prepareRestore())
        let controller = try makeController(for: model)

        try await controller.reinstateInterruptedSavedSession()

        #expect(controller.state.isSaved)
    }

    // MARK: Closing

    @Test func savingAVirtualMachineThatIsNotRunningIsRefused() async throws {
        let controller = try makeController(for: try makeVirtualMachine())

        await #expect(throws: SavedSessionError.self) {
            try await controller.saveAndStop()
        }
    }

    @Test func repeatedSaveRequestsAfterTheSessionWasSavedHaveNothingLeftToDo() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let controller = try makeController(for: model)

        try await controller.saveAndStop()

        #expect(controller.state.isSaved)
    }

    @Test func shuttingDownASavedVirtualMachineReturnsImmediately() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let controller = try makeController(for: model)

        try await controller.shutDownAndWait()

        #expect(controller.state.isSaved)
    }

    @Test func pendingOperationsFinishImmediatelyWhenThereAreNone() async throws {
        let controller = try makeController(for: try makeVirtualMachine())

        await controller.waitForPendingOperations()
    }

    @Test func lifecycleStageMatchesState() throws {
        let model = try makeVirtualMachine()
        #expect(try makeController(for: model).lifecycleStage == .notRunning)

        try saveSession(in: model)
        #expect(try makeController(for: model).lifecycleStage == .notRunning)
    }

    // MARK: Eligibility

    @Test func eligibilityExplainsWhySavingIsUnavailableBeforeStarting() throws {
        let model = try makeVirtualMachine()

        let supported = try makeController(for: model)
        #expect(supported.saveEligibility.isSupported)

        let recovery = try makeController(for: model, options: VMSessionOptions(bootInRecoveryMode: true))
        #expect(recovery.saveEligibility.primaryIssue == .specialBootMode("recovery mode"))
    }

    @Test func stateHelpersDescribeEveryState() {
        let saved = VMState.saved(VBSavedSessionDescriptor(id: UUID(), date: nil, status: .ready))

        #expect(saved.canStart)
        #expect(saved.isSavedSessionPresentation)
        #expect(!saved.isActive)
        #expect(!saved.canSaveAndClose)

        #expect(VMState.recoveryRequired(.interruptedAfterResume).canStart)
        #expect(VMState.idle.canStart)
        #expect(VMState.stopped(nil).canStart)

        #expect(VMState.starting(nil).isActive)
        #expect(!VMState.starting(nil).canStart)
        #expect(VMState.restoring(nil, .validating).isPerformingSessionOperation)
        #expect(!VMState.restoring(nil, .validating).canStart)
    }
}

// MARK: - Restoring

extension VMControllerSavedSessionTests {
    private func readDisk(_ model: VBVirtualMachine) throws -> Data {
        try Data(contentsOf: model.bundleURL.appending(path: "Disk.img"))
    }

    /// The hardware model in these bundles isn't real, so the framework can't construct the virtual machine.
    /// Whatever happens after that must leave the saved session exactly as it was.
    @Test func failedRestoreKeepsTheSavedSessionAndNeverFallsBackToColdBoot() async throws {
        var model = try makeVirtualMachine()

        /// A pending resize must not be applied when resuming. Resizing the disk under a saved session would corrupt it.
        var boot = try #require(model.configuration.hardware.storageDevices.first { $0.isBootVolume })
        if case .managedImage(var image) = boot.backing {
            image.resizePending = true
            boot.backing = .managedImage(image)
            model.configuration.hardware.addOrUpdate(boot)
            try model.saveMetadata()
        }

        try saveSession(in: model)

        try Data("diverged".utf8).write(to: model.bundleURL.appending(path: "Disk.img"))

        let controller = try makeController(for: model)
        var observedStates = [String]()
        let observation = controller.$state.sink { observedStates.append("\($0)".prefix(12).description) }
        defer { observation.cancel() }

        await #expect {
            try await controller.start()
        } throws: { error in
            guard case SavedSessionError.restoreFailed = error else { return false }
            return true
        }

        #expect(controller.state.isSaved, "the saved session must still be there to try again")
        #expect(SavedSessionStorage(bundleURL: model.bundleURL).inspect()?.status == .ready)
        #expect(try readDisk(model) == Data("diverged".utf8), "a failed restore must put the working disk back")
        #expect(!SavedSessionLayout(bundleURL: model.bundleURL).transactionURL.isDirectory)
        #expect(!observedStates.contains { $0.hasPrefix("starting") || $0.hasPrefix("running") || $0.hasPrefix("stopped") }, "no cold boot may be attempted: \(observedStates)")

        let reloaded = try VBVirtualMachine(bundleURL: model.bundleURL, isNewInstall: false, createIfNeeded: false)
        #expect(reloaded.hasPendingDiskImageResizes, "the resize must not have been performed")
    }

    @Test func restoreOfSessionWithMissingResourceFailsWithoutRegeneratingAnything() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)

        let layout = SavedSessionLayout(bundleURL: model.bundleURL)
        let manifest = try PropertyListDecoder().decode(SavedSessionManifest.self, from: Data(contentsOf: layout.manifestURL))
        try FileManager.default.removeItem(at: layout.packageURL.appending(path: try #require(manifest.resource(with: .machineIdentifier)).packagePath))

        let controller = try makeController(for: model)

        await #expect(throws: SavedSessionError.self) {
            try await controller.start()
        }

        guard case .recoveryRequired(.unavailable) = controller.state else {
            Issue.record("expected the session to be unavailable, got \(controller.state)")
            return
        }
        #expect(try Data(contentsOf: model.machineIdentifierURL) == Data("machine identifier".utf8), "identity must never be regenerated")
    }

    @Test func discardingThenStartingIsTheOnlyWayToBootInsteadOfResuming() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let controller = try makeController(for: model)

        try await controller.discardSavedSession()

        #expect(SavedSessionStorage(bundleURL: model.bundleURL).inspect() == nil)
        #expect(try readDisk(model) == diskContents)
    }
}

extension VMControllerSavedSessionTests {
    /// Nothing may change a virtual machine's bundle while it's being copied.
    @Test func duplicationHoldsBackEverythingThatChangesTheBundle() async throws {
        let model = try makeVirtualMachine()
        try saveSession(in: model)
        let controller = try makeController(for: model)
        let library = VMLibraryController.preview

        /// Keeps the controller busy so that the duplication has to wait for its turn, with its exclusion already in place.
        var releaseController: CheckedContinuation<Void, Never>?
        let busy = Task { @MainActor in
            await controller.performExclusively {
                await withCheckedContinuation { releaseController = $0 }
            }
        }
        for _ in 0..<5 { await Task.yield() }

        let duplicating = Task { @MainActor in try await library.duplicate(model) }
        for _ in 0..<5 { await Task.yield() }

        #expect(library.isBeingDuplicated(model))
        #expect(throws: Failure.self) { try library.rename(model, to: "Renamed VM") }

        /// Queued behind the duplication, so it can only happen after the copy is complete.
        let discarding = Task { @MainActor in try await controller.discardSavedSession() }
        for _ in 0..<5 { await Task.yield() }

        releaseController?.resume()
        await busy.value

        let copy = try await duplicating.value
        try await discarding.value

        #expect(copy.savedSession?.status == .ready, "the copy must have been made before the session was discarded")
        #expect(controller.savedSession == nil)
        #expect(!library.isBeingDuplicated(model))
    }
}

private extension URL {
    var isDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

// MARK: - Active Copies and Legacy States

@MainActor
final class SavedSessionIdentityTests {
    private let directoryURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "SavedSessionIdentityTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func makeVirtualMachine(named name: String, identity: String, macAddress: String) throws -> VBVirtualMachine {
        var model = try VBVirtualMachine(
            bundleURL: directoryURL.appending(path: "\(name).\(VBVirtualMachine.bundleExtension)", directoryHint: .isDirectory),
            isNewInstall: true
        )
        model.configuration.hardware.networkDevices = [VBNetworkDevice(id: "NAT", name: "NAT", kind: .NAT, macAddress: macAddress)]
        try model.saveMetadata()
        try Data(identity.utf8).write(to: model.machineIdentifierURL)
        return model
    }

    @Test func copyWithTheSameGuestIdentityCannotRunAlongsideTheOriginal() throws {
        let original = try makeVirtualMachine(named: "Original", identity: "same", macAddress: "AA:BB:CC:DD:EE:01")
        let copy = try VMBundleDuplicator().duplicate(bundleAt: original.bundleURL, to: directoryURL.appending(path: "Copy.\(VBVirtualMachine.bundleExtension)"))

        let conflicts = SavedSessionActiveCopyConflict.conflicts(for: copy, macAddresses: ["aa:bb:cc:dd:ee:01"], among: [original])

        #expect(conflicts.map(\.virtualMachineID) == [original.id])
        #expect(conflicts.first?.reason == .guestIdentity)
        #expect(conflicts.first?.explanation.contains("Original") == true)
    }

    @Test func conflictingSavedAddressIsDetectedEvenWhenIdentitiesDiffer() throws {
        let running = try makeVirtualMachine(named: "Running", identity: "one", macAddress: "AA:BB:CC:DD:EE:02")
        let resuming = try makeVirtualMachine(named: "Resuming", identity: "two", macAddress: "AA:BB:CC:DD:EE:03")

        let conflicts = SavedSessionActiveCopyConflict.conflicts(for: resuming, macAddresses: ["AA:BB:CC:DD:EE:02"], among: [running])

        #expect(conflicts.first?.reason == .macAddress("AA:BB:CC:DD:EE:02"))
    }

    @Test func unrelatedVirtualMachinesDoNotConflict() throws {
        let running = try makeVirtualMachine(named: "Running", identity: "one", macAddress: "AA:BB:CC:DD:EE:04")
        let resuming = try makeVirtualMachine(named: "Resuming", identity: "two", macAddress: "AA:BB:CC:DD:EE:05")

        #expect(SavedSessionActiveCopyConflict.conflicts(for: resuming, macAddresses: ["AA:BB:CC:DD:EE:05"], among: [running]).isEmpty)
        #expect(SavedSessionActiveCopyConflict.conflicts(for: resuming, macAddresses: ["AA:BB:CC:DD:EE:05"], among: [resuming]).isEmpty, "a virtual machine doesn't conflict with itself")
    }

    @Test func legacySavedStatesAreNeverTouched() throws {
        let original = try makeVirtualMachine(named: "Original", identity: "same", macAddress: "AA:BB:CC:DD:EE:06")

        let legacyPackage = directoryURL
            .appending(path: "_SavedState", directoryHint: .isDirectory)
            .appending(path: original.uuid.uuidString, directoryHint: .isDirectory)
            .appending(path: "Old.vbst", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyPackage, withIntermediateDirectories: true)
        let info = Data("legacy info".utf8)
        let state = Data("legacy state".utf8)
        try info.write(to: legacyPackage.appending(path: "Info.plist"))
        try state.write(to: legacyPackage.appending(path: "State.vzvmsave"))

        /// Everything the new implementation does to a virtual machine that has a legacy state.
        let storage = SavedSessionStorage(bundleURL: original.bundleURL)
        try storage.recover()
        try storage.discard()
        _ = try VMBundleDuplicator().duplicate(bundleAt: original.bundleURL, to: directoryURL.appending(path: "Copy.\(VBVirtualMachine.bundleExtension)"))
        _ = try VBVirtualMachine(bundleURL: original.bundleURL, isNewInstall: false, createIfNeeded: false)

        #expect(try Data(contentsOf: legacyPackage.appending(path: "Info.plist")) == info)
        #expect(try Data(contentsOf: legacyPackage.appending(path: "State.vzvmsave")) == state)
        #expect(try FileManager.default.contentsOfDirectory(atPath: legacyPackage.path).sorted() == ["Info.plist", "State.vzvmsave"])
    }
}
