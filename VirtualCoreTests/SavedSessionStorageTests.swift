import XCTest
import Virtualization
@testable import VirtualCore

/// Lets a test fail or "crash" a saved session transaction at any step.
final class FaultInjectingFileSystem: SavedSessionFileSystem, @unchecked Sendable {
    enum Mode {
        /// Only the chosen operation fails, which the code under test gets a chance to clean up after.
        case transient
        /// The chosen operation and every operation after it fail, like a power loss.
        case crash
    }

    struct InjectedFailure: Error {}

    private let base = DefaultSavedSessionFileSystem()
    private let lock = NSLock()
    private var counter = 0

    var failingOperation: Int?
    var mode = Mode.transient
    var failure: Error = InjectedFailure()

    /// How many mutating operations have been attempted.
    var operationCount: Int { lock.withLock { counter } }

    private func mutate() throws {
        try lock.withLock {
            counter += 1
            guard let failingOperation else { return }
            switch mode {
            case .transient:
                if counter == failingOperation { throw failure }
            case .crash:
                if counter >= failingOperation { throw failure }
            }
        }
    }

    func exists(_ url: URL) -> Bool { base.exists(url) }
    func byteCount(of url: URL) -> UInt64? { base.byteCount(of: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }
    func read(_ url: URL) throws -> Data { try base.read(url) }

    func createDirectory(_ url: URL) throws { try mutate(); try base.createDirectory(url) }
    func copy(from source: URL, to destination: URL) throws { try mutate(); try base.copy(from: source, to: destination) }
    func clone(from source: URL, to destination: URL) throws { try mutate(); try base.clone(from: source, to: destination) }
    func move(from source: URL, to destination: URL, replacingExisting: Bool) throws {
        try mutate()
        try base.move(from: source, to: destination, replacingExisting: replacingExisting)
    }
    func remove(_ url: URL) throws { try mutate(); try base.remove(url) }
    func writeDurably(_ data: Data, to url: URL) throws { try mutate(); try base.writeDurably(data, to: url) }
    func synchronizeDirectory(_ url: URL) throws { try mutate(); try base.synchronizeDirectory(url) }
    func synchronizeFile(_ url: URL) throws { try mutate(); try base.synchronizeFile(url) }
}

final class SavedSessionStorageTests: XCTestCase {
    private var bundleURL: URL!

    private let originalDisk = Data("disk contents at save time".utf8)
    private let originalAux = Data("aux storage at save time".utf8)
    private let stateData = Data("memory and device state".utf8)

    override func setUpWithError() throws {
        bundleURL = FileManager.default.temporaryDirectory
            .appending(path: "SavedSessionStorageTests-\(UUID().uuidString).vbvm", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        try originalDisk.write(to: path("Disk.img"))
        try originalAux.write(to: path("AuxiliaryStorage"))
        try Data("machine".utf8).write(to: path("MachineIdentifier"))
        try Data("hardware".utf8).write(to: path("HardwareModel"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleURL)
    }

    // MARK: Helpers

    private func path(_ name: String) -> URL { bundleURL.appending(path: name) }

    private func makeStorage(_ fileSystem: SavedSessionFileSystem = DefaultSavedSessionFileSystem()) -> SavedSessionStorage {
        SavedSessionStorage(bundleURL: bundleURL, fileSystem: fileSystem, hostECID: 42)
    }

    private func makePlan(withMedia: Bool = false) -> SavedSessionCapturePlan {
        var resources: [SavedSessionCapturePlan.ResourceSource] = [
            .init(id: "disk", role: .disk, sourceURL: path("Disk.img"), workingPath: "Disk.img"),
            .init(id: "aux", role: .auxiliaryStorage, sourceURL: path("AuxiliaryStorage"), workingPath: "AuxiliaryStorage"),
            .init(id: "mid", role: .machineIdentifier, sourceURL: path("MachineIdentifier"), workingPath: "MachineIdentifier"),
            .init(id: "hw", role: .hardwareModel, sourceURL: path("HardwareModel"), workingPath: "HardwareModel")
        ]

        if withMedia {
            let media = bundleURL.deletingLastPathComponent().appending(path: "media-\(UUID().uuidString).img")
            try? Data("guest additions".utf8).write(to: media)
            resources.append(.init(id: "media", role: .guestAdditionsMedia, sourceURL: media, workingPath: SavedSessionLayout.guestAdditionsMediaWorkingPath))
        }

        return SavedSessionCapturePlan(
            resources: resources,
            configuration: .default,
            runtimeDescription: SavedSessionRuntimeDescription(configuration: VZVirtualMachineConfiguration()),
            screenshotSourceURL: nil,
            wasPausedBeforeSave: false,
            memorySize: 1
        )
    }

    @discardableResult
    private func capture(with storage: SavedSessionStorage, plan: SavedSessionCapturePlan? = nil) throws -> VBSavedSessionDescriptor {
        let staged = try storage.stageCapture(plan ?? makePlan())
        try stateData.write(to: staged.stateFileURL)
        return try storage.publish(staged)
    }

    private func readWorking(_ name: String) throws -> Data { try Data(contentsOf: path(name)) }

    private func writeWorking(_ name: String, _ string: String) throws { try Data(string.utf8).write(to: path(name)) }

    private func bundleEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: bundleURL.path).sorted()
    }

    private func assertNoTransientLeftovers(file: StaticString = #filePath, line: UInt = #line) throws {
        let leftovers = try bundleEntries().filter { SavedSessionLayout.isTransientName($0) }
        XCTAssertEqual(leftovers, [], file: file, line: line)
    }

    // MARK: Capture

    func testCapturePublishesCompletePackageWithRelativePaths() throws {
        let storage = makeStorage()

        let descriptor = try capture(with: storage, plan: makePlan(withMedia: true))

        XCTAssertEqual(descriptor.status, .ready)
        XCTAssertEqual(storage.inspect(), descriptor)

        let manifest = try PropertyListDecoder().decode(SavedSessionManifest.self, from: Data(contentsOf: storage.layout.manifestURL))

        XCTAssertEqual(Set(manifest.resources.map(\.role)), [.disk, .auxiliaryStorage, .machineIdentifier, .hardwareModel, .guestAdditionsMedia])
        XCTAssertEqual(manifest.stateFileByteCount, UInt64(stateData.count))

        for resource in manifest.resources {
            XCTAssertFalse(resource.packagePath.hasPrefix("/"), "package paths must be relative")
            XCTAssertFalse(resource.workingPath.hasPrefix("/"), "working paths must be relative")
            XCTAssertTrue(FileManager.default.fileExists(atPath: storage.layout.packageURL.appending(path: resource.packagePath).path))
        }

        XCTAssertEqual(try Data(contentsOf: storage.layout.packageURL.appending(path: manifest.resource(with: .disk)!.packagePath)), originalDisk)
        XCTAssertEqual(try readWorking("Disk.img"), originalDisk, "capturing must not modify the working disk")
        try assertNoTransientLeftovers()
    }

    func testCaptureClonesAreIndependentFromWorkingFiles() throws {
        let storage = makeStorage()
        try capture(with: storage)

        try writeWorking("Disk.img", "changed after save")

        let manifest = try PropertyListDecoder().decode(SavedSessionManifest.self, from: Data(contentsOf: storage.layout.manifestURL))
        XCTAssertEqual(try Data(contentsOf: storage.layout.packageURL.appending(path: manifest.resource(with: .disk)!.packagePath)), originalDisk)
    }

    func testMissingResourceFailsWithoutLeavingAnything() throws {
        let storage = makeStorage()
        try FileManager.default.removeItem(at: path("AuxiliaryStorage"))

        XCTAssertThrowsError(try storage.stageCapture(makePlan())) { error in
            guard case SavedSessionError.missingResource = error else { return XCTFail("unexpected error \(error)") }
        }

        XCTAssertNil(storage.inspect())
        try assertNoTransientLeftovers()
    }

    func testCloneFailureLeavesNoPackage() throws {
        let fileSystem = FaultInjectingFileSystem()
        let storage = makeStorage(fileSystem)

        /// Operations: create staging, create resources dir, then clones.
        fileSystem.failingOperation = 4
        fileSystem.failure = SavedSessionError.cloneUnsupported(path("Disk.img"))

        XCTAssertThrowsError(try storage.stageCapture(makePlan()))

        XCTAssertNil(storage.inspect())
        try assertNoTransientLeftovers()
        XCTAssertEqual(try readWorking("Disk.img"), originalDisk)
    }

    func testDiskFullFailureLeavesNoPackage() throws {
        let fileSystem = FaultInjectingFileSystem()
        let storage = makeStorage(fileSystem)

        fileSystem.failingOperation = 5
        fileSystem.failure = SavedSessionError.diskFull

        let staged: SavedSessionStagedCapture?
        do {
            staged = try storage.stageCapture(makePlan())
        } catch {
            staged = nil
            guard case SavedSessionError.diskFull = error else { return XCTFail("unexpected error \(error)") }
        }

        if let staged {
            try stateData.write(to: staged.stateFileURL)
            XCTAssertThrowsError(try storage.publish(staged))
        }

        XCTAssertNil(storage.inspect())
        try assertNoTransientLeftovers()
    }

    func testPublishRequiresStateFile() throws {
        let storage = makeStorage()
        let staged = try storage.stageCapture(makePlan())

        XCTAssertThrowsError(try storage.publish(staged))
        XCTAssertNil(storage.inspect())
        try assertNoTransientLeftovers()
    }

    func testSecondCaptureIsRejectedWhileSessionExists() throws {
        let storage = makeStorage()
        try capture(with: storage)

        XCTAssertThrowsError(try storage.stageCapture(makePlan())) { error in
            guard case SavedSessionError.activeSessionConflict = error else { return XCTFail("unexpected error \(error)") }
        }
        XCTAssertEqual(storage.inspect()?.status, .ready)
    }

    /// Failing at any step of a save either publishes a complete package or nothing at all.
    func testSaveFailureAtEveryStepNeverPublishesIncompletePackage() throws {
        let probe = FaultInjectingFileSystem()
        try capture(with: makeStorage(probe))
        let operations = probe.operationCount
        try FileManager.default.removeItem(at: makeStorage().layout.packageURL)

        for mode in [FaultInjectingFileSystem.Mode.transient, .crash] {
            for step in 1...operations {
                let fileSystem = FaultInjectingFileSystem()
                fileSystem.failingOperation = step
                fileSystem.mode = mode

                do { try capture(with: makeStorage(fileSystem)) } catch { }

                /// Whatever happened, a fresh run of the app must see either no session or a complete one.
                let recovered = makeStorage()
                try recovered.recover()

                if let descriptor = recovered.inspect() {
                    XCTAssertEqual(descriptor.status, .ready, "step \(step) \(mode) published a package that isn't valid")
                    try FileManager.default.removeItem(at: recovered.layout.packageURL)
                }

                try assertNoTransientLeftovers()
                XCTAssertEqual(try readWorking("Disk.img"), originalDisk)
            }
        }
    }

    // MARK: Restore

    func testRestoreInstallsSavedResourcesAndCompletes() throws {
        let storage = makeStorage()
        try capture(with: storage, plan: makePlan(withMedia: true))

        try writeWorking("Disk.img", "diverged working disk")

        let preparation = try storage.prepareRestore()

        XCTAssertEqual(try readWorking("Disk.img"), originalDisk, "working disk must belong to the same moment as the memory")
        XCTAssertEqual(try readWorking("AuxiliaryStorage"), originalAux)
        XCTAssertEqual(try Data(contentsOf: preparation.stateFileURL), stateData)
        XCTAssertNotNil(preparation.guestAdditionsMediaURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparation.guestAdditionsMediaURL!.path))

        try storage.markConsumed(preparation)
        XCTAssertTrue(storage.hasPendingConsumedRestore())

        try storage.completeRestore()

        XCTAssertNil(storage.inspect())
        XCTAssertFalse(storage.hasPendingConsumedRestore())
        /// The guest additions image stays installed while the restored virtual machine runs.
        XCTAssertEqual(try bundleEntries().filter { $0.hasPrefix(".vbsession") }, [SavedSessionLayout.mediaDirectoryName])

        try storage.removeWorkingMedia()
        try assertNoTransientLeftovers()
    }

    func testRestoreDoesNotRegenerateMissingResources() throws {
        let storage = makeStorage()
        try capture(with: storage)

        let manifest = try PropertyListDecoder().decode(SavedSessionManifest.self, from: Data(contentsOf: storage.layout.manifestURL))
        try FileManager.default.removeItem(at: storage.layout.packageURL.appending(path: manifest.resource(with: .auxiliaryStorage)!.packagePath))

        XCTAssertThrowsError(try storage.prepareRestore()) { error in
            guard case SavedSessionError.missingResource = error else { return XCTFail("unexpected error \(error)") }
        }

        guard case .recoveryRequired(.unavailable)? = storage.inspect()?.status else { return XCTFail("session should be unavailable") }
        XCTAssertEqual(try readWorking("AuxiliaryStorage"), originalAux)
    }

    func testRestoreRejectsSessionFromDifferentHost() throws {
        try capture(with: makeStorage())

        let otherHost = SavedSessionStorage(bundleURL: bundleURL, hostECID: 99)

        XCTAssertThrowsError(try otherHost.prepareRestore()) { error in
            guard case SavedSessionError.hostMismatch = error else { return XCTFail("unexpected error \(error)") }
        }
    }

    func testRestoreRejectsNewerFormat() throws {
        let storage = makeStorage()
        try capture(with: storage)

        var manifest = try PropertyListDecoder().decode(SavedSessionManifest.self, from: Data(contentsOf: storage.layout.manifestURL))
        manifest.formatVersion = SavedSessionManifest.currentFormatVersion + 1
        try PropertyListEncoder().encode(manifest).write(to: storage.layout.manifestURL)

        XCTAssertThrowsError(try storage.prepareRestore()) { error in
            guard case SavedSessionError.unsupportedFormat = error else { return XCTFail("unexpected error \(error)") }
        }
    }

    /// Failing or crashing at any step before execution can begin leaves the virtual machine exactly as it was.
    func testRestoreFailureBeforeConsumptionAtEveryStepRollsBack() throws {
        let setup = makeStorage()
        try capture(with: setup, plan: makePlan(withMedia: true))

        let probe = FaultInjectingFileSystem()
        _ = try makeStorage(probe).prepareRestore()
        let operations = probe.operationCount
        try makeStorage().cancelRestore()

        let divergedDisk = "disk written after the session was saved"

        for mode in [FaultInjectingFileSystem.Mode.transient, .crash] {
            for step in 1...operations {
                try writeWorking("Disk.img", divergedDisk)

                let fileSystem = FaultInjectingFileSystem()
                fileSystem.failingOperation = step
                fileSystem.mode = mode

                XCTAssertThrowsError(try makeStorage(fileSystem).prepareRestore(), "step \(step) \(mode)")

                /// Like a relaunch after the interruption.
                let recovered = makeStorage()
                try recovered.recover()

                XCTAssertEqual(try readWorking("Disk.img"), Data(divergedDisk.utf8), "step \(step) \(mode) didn't restore the working disk")
                XCTAssertEqual(try readWorking("AuxiliaryStorage"), originalAux, "step \(step) \(mode)")
                XCTAssertEqual(recovered.inspect()?.status, .ready, "step \(step) \(mode) must keep the save available")
                XCTAssertFalse(FileManager.default.fileExists(atPath: recovered.layout.transactionURL.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: recovered.layout.mediaDirectoryURL.path), "step \(step) \(mode)")
            }
        }

        /// And the save is still good after all of that.
        let preparation = try makeStorage().prepareRestore()
        XCTAssertEqual(try readWorking("Disk.img"), originalDisk)
        try makeStorage().markConsumed(preparation)
        try makeStorage().completeRestore()
    }

    func testInterruptionAfterConsumptionIsNeverReplayed() throws {
        let storage = makeStorage()
        try capture(with: storage)

        let preparation = try storage.prepareRestore()
        try storage.markConsumed(preparation)

        /// The guest runs and writes to the disk, then the app dies.
        try writeWorking("Disk.img", "newer disk contents")

        let relaunched = makeStorage()

        XCTAssertEqual(try relaunched.recover(), .consumedSessionRetained)
        XCTAssertEqual(relaunched.inspect()?.status, .recoveryRequired(.interruptedAfterResume))

        XCTAssertThrowsError(try relaunched.prepareRestore()) { error in
            guard case SavedSessionError.recoveryRequired(.interruptedAfterResume) = error else { return XCTFail("unexpected error \(error)") }
        }

        XCTAssertEqual(try readWorking("Disk.img"), Data("newer disk contents".utf8), "newer disk contents must not be overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: relaunched.layout.packageURL.path), "evidence must be preserved")
    }

    func testDiscardAfterInterruptionKeepsNewerDisks() throws {
        let storage = makeStorage()
        try capture(with: storage)
        try storage.markConsumed(try storage.prepareRestore())
        try writeWorking("Disk.img", "newer disk contents")

        try makeStorage().discard()

        XCTAssertNil(makeStorage().inspect())
        XCTAssertEqual(try readWorking("Disk.img"), Data("newer disk contents".utf8))
        try assertNoTransientLeftovers()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.layout.transactionURL.path))
    }

    func testReinstatingInterruptedSessionRewindsOnlyWhenAsked() throws {
        let storage = makeStorage()
        try capture(with: storage)
        try storage.markConsumed(try storage.prepareRestore())
        try writeWorking("Disk.img", "newer disk contents")

        let relaunched = makeStorage()
        try relaunched.reinstateConsumedSession()

        XCTAssertEqual(relaunched.inspect()?.status, .ready)

        _ = try relaunched.prepareRestore()
        XCTAssertEqual(try readWorking("Disk.img"), originalDisk)
    }

    func testCleanupFailureNeverMakesConsumedPackageRestorableAgain() throws {
        let setup = makeStorage()
        try capture(with: setup)
        let preparation = try setup.prepareRestore()
        try setup.markConsumed(preparation)

        let probe = FaultInjectingFileSystem()
        try makeStorage(probe).completeRestore()
        let operations = probe.operationCount

        for mode in [FaultInjectingFileSystem.Mode.transient, .crash] {
            for step in 1...operations {
                try? FileManager.default.removeItem(at: setup.layout.packageURL)
                try? FileManager.default.removeItem(at: setup.layout.transactionURL)
                try capture(with: makeStorage())
                let prep = try makeStorage().prepareRestore()
                try makeStorage().markConsumed(prep)

                let fileSystem = FaultInjectingFileSystem()
                fileSystem.failingOperation = step
                fileSystem.mode = mode
                try? makeStorage(fileSystem).completeRestore()

                let relaunched = makeStorage()
                try? relaunched.recover()

                switch relaunched.inspect()?.status {
                case nil, .recoveryRequired(.interruptedAfterResume)?:
                    break
                default:
                    XCTFail("step \(step) \(mode): consumed package became restorable again")
                }

                XCTAssertThrowsError(try relaunched.prepareRestore(), "step \(step) \(mode)")
            }
        }
    }

    func testRecoveryRemovesStaleStagingDirectories() throws {
        let stale = bundleURL.appending(path: SavedSessionLayout.stagingPrefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

        try makeStorage().recover()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testVirtualMachineWithoutSavedSessionHasNoDescriptor() {
        XCTAssertNil(makeStorage().inspect())
    }
}
