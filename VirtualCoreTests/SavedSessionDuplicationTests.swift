import XCTest
@testable import VirtualCore

final class SavedSessionDuplicationTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "SavedSessionDuplicationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    // MARK: Helpers

    private func bundleURL(_ name: String) -> URL {
        directoryURL.appending(path: "\(name).\(VBVirtualMachine.bundleExtension)", directoryHint: .isDirectory)
    }

    /// Creates a virtual machine bundle with files that stand in for its disk and identity.
    private func makeVirtualMachine(named name: String = "Original") throws -> VBVirtualMachine {
        var model = try VBVirtualMachine(bundleURL: bundleURL(name), isNewInstall: true)
        model.metadata.installFinished = true
        try model.saveMetadata()

        try Data("disk".utf8).write(to: model.bundleURL.appending(path: "Disk.img"))
        try Data("aux".utf8).write(to: model.auxiliaryStorageURL)
        try Data("machine identifier".utf8).write(to: model.machineIdentifierURL)
        try Data("hardware model".utf8).write(to: model.hardwareModelURL)

        return model
    }

    private func saveSession(in model: VBVirtualMachine) throws {
        let storage = SavedSessionStorage(bundleURL: model.bundleURL, hostECID: ProcessInfo.processInfo.machineECID)

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

    private func visibleEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
    }

    // MARK: Duplication

    func testDuplicateOfSavedVirtualMachineIsAnIndependentSavedVirtualMachine() throws {
        let created = try makeVirtualMachine()
        try saveSession(in: created)

        /// Leftovers of operations that were in progress must not be copied.
        for name in [SavedSessionLayout.stagingPrefix + "x", SavedSessionLayout.transactionName, SavedSessionLayout.mediaDirectoryName] {
            try FileManager.default.createDirectory(at: created.bundleURL.appending(path: name), withIntermediateDirectories: true)
        }

        let original = try VBVirtualMachine(bundleURL: created.bundleURL, isNewInstall: false, createIfNeeded: false)
        XCTAssertEqual(original.savedSession?.status, .ready)

        let copyURL = bundleURL("Copy of Original")
        let copy = try VMBundleDuplicator().duplicate(bundleAt: original.bundleURL, to: copyURL)

        XCTAssertEqual(copy.bundleURL, copyURL)
        XCTAssertNotEqual(copy.uuid, original.uuid, "the copy needs its own library identity")
        XCTAssertEqual(try Data(contentsOf: copy.machineIdentifierURL), try Data(contentsOf: original.machineIdentifierURL), "guest identity must be preserved")
        XCTAssertEqual(copy.configuration, original.configuration)

        XCTAssertEqual(copy.savedSession?.status, .ready)
        XCTAssertEqual(copy.savedSession?.id, original.savedSession?.id)

        for name in [SavedSessionLayout.stagingPrefix + "x", SavedSessionLayout.transactionName, SavedSessionLayout.mediaDirectoryName] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: copy.bundleURL.appending(path: name).path), "\(name) must not be duplicated")
        }
        XCTAssertEqual(try visibleEntries().filter { $0.hasPrefix(".") }, [], "no temporary data may be left behind")

        /// Resuming the copy must not touch the original.
        try Data("copy diverged".utf8).write(to: copy.bundleURL.appending(path: "Disk.img"))

        let copyStorage = SavedSessionStorage(bundleURL: copy.bundleURL, hostECID: ProcessInfo.processInfo.machineECID)
        let preparation = try copyStorage.prepareRestore()
        try copyStorage.markConsumed(preparation)
        try copyStorage.completeRestore()

        XCTAssertNil(copyStorage.inspect())
        XCTAssertEqual(SavedSessionStorage(bundleURL: original.bundleURL, hostECID: ProcessInfo.processInfo.machineECID).inspect()?.status, .ready, "the original keeps its session")
        XCTAssertEqual(try Data(contentsOf: original.bundleURL.appending(path: "Disk.img")), Data("disk".utf8))
    }

    func testFailedDuplicationLeavesNoVisiblePartialVirtualMachine() throws {
        let original = try makeVirtualMachine()
        try saveSession(in: original)

        let copyURL = bundleURL("Copy of Original")

        let probe = FaultInjectingFileSystem()
        _ = try VMBundleDuplicator(fileSystem: probe).duplicate(bundleAt: original.bundleURL, to: copyURL)
        let operations = probe.operationCount
        try FileManager.default.removeItem(at: copyURL)

        for mode in [FaultInjectingFileSystem.Mode.transient, .crash] {
            for step in 1...operations {
                let fileSystem = FaultInjectingFileSystem()
                fileSystem.failingOperation = step
                fileSystem.mode = mode

                XCTAssertThrowsError(try VMBundleDuplicator(fileSystem: fileSystem).duplicate(bundleAt: original.bundleURL, to: copyURL), "step \(step) \(mode)")

                XCTAssertFalse(FileManager.default.fileExists(atPath: copyURL.path), "step \(step) \(mode) left a partial virtual machine")
                XCTAssertEqual(SavedSessionStorage(bundleURL: original.bundleURL, hostECID: ProcessInfo.processInfo.machineECID).inspect()?.status, .ready)

                /// Anything a crash leaves behind is hidden from the library, which only lists visible bundles.
                for entry in try visibleEntries() where entry != original.bundleURL.lastPathComponent {
                    XCTAssertTrue(entry.hasPrefix("."), "step \(step) \(mode) left visible entry \(entry)")
                    try FileManager.default.removeItem(at: directoryURL.appending(path: entry))
                }
            }
        }
    }

    func testDuplicateOfInterruptedSessionStillRequiresRecovery() throws {
        let created = try makeVirtualMachine()
        try saveSession(in: created)

        let storage = SavedSessionStorage(bundleURL: created.bundleURL)
        try storage.markConsumed(try storage.prepareRestore())
        try Data("newer disk".utf8).write(to: created.bundleURL.appending(path: "Disk.img"))

        let copy = try VMBundleDuplicator().duplicate(bundleAt: created.bundleURL, to: bundleURL("Copy of Original"))

        XCTAssertEqual(copy.savedSession?.status, .recoveryRequired(.interruptedAfterResume), "the copy must not look ready")

        let copyStorage = SavedSessionStorage(bundleURL: copy.bundleURL)
        XCTAssertThrowsError(try copyStorage.prepareRestore(), "resuming the copy must not silently rewind its newer disks")
        XCTAssertEqual(try Data(contentsOf: copy.bundleURL.appending(path: "Disk.img")), Data("newer disk".utf8))
    }

    func testDuplicateOfVirtualMachineWithUnfinishedRestoreStartsFromRolledBackFiles() throws {
        let created = try makeVirtualMachine()
        try saveSession(in: created)
        try Data("diverged".utf8).write(to: created.bundleURL.appending(path: "Disk.img"))

        /// An interruption halfway through installing the saved resources.
        let storage = SavedSessionStorage(bundleURL: created.bundleURL)
        _ = try storage.prepareRestore()

        let copy = try VMBundleDuplicator().duplicate(bundleAt: created.bundleURL, to: bundleURL("Copy of Original"))

        XCTAssertEqual(try Data(contentsOf: copy.bundleURL.appending(path: "Disk.img")), Data("diverged".utf8))
        XCTAssertEqual(copy.savedSession?.status, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: SavedSessionLayout(bundleURL: copy.bundleURL).transactionURL.path))
    }

    func testDuplicationRefusesExistingDestination() throws {
        let original = try makeVirtualMachine()
        let existing = try makeVirtualMachine(named: "Copy of Original")
        let existingDisk = try Data(contentsOf: existing.bundleURL.appending(path: "Disk.img"))

        XCTAssertThrowsError(try VMBundleDuplicator().duplicate(bundleAt: original.bundleURL, to: existing.bundleURL))

        XCTAssertEqual(try Data(contentsOf: existing.bundleURL.appending(path: "Disk.img")), existingDisk)
        XCTAssertEqual(try visibleEntries().filter { $0.hasPrefix(".") }, [])
    }

    // MARK: External Disk Images

    private func makeExternalImage(named name: String, contents: String) throws -> URL {
        let url = directoryURL.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func addExternalDevice(_ url: URL, to model: inout VBVirtualMachine, readOnly: Bool = false) -> VBStorageDevice {
        let device = VBStorageDevice(isBootVolume: false, isReadOnly: readOnly, isUSBMassStorageDevice: true, backing: .customImage(url))
        model.configuration.hardware.addOrUpdate(device)
        return device
    }

    func testCopyingExternalDiskImagesPreservesIdentityAndOrderWithoutTouchingSources() async throws {
        var model = try makeVirtualMachine()
        let first = try makeExternalImage(named: "Data.img", contents: "first")
        let second = try makeExternalImage(named: "Installer.iso", contents: "second")
        let a = addExternalDevice(first, to: &model)
        let b = addExternalDevice(second, to: &model, readOnly: true)

        let originalDevices = model.configuration.hardware.storageDevices

        let result = try await ExternalDiskImageCopier().copyExternalDiskImages(of: model)

        XCTAssertEqual(result.devices.map(\.id), originalDevices.map(\.id), "device identity and order must be preserved")
        XCTAssertEqual(result.devices.map(\.isReadOnly), originalDevices.map(\.isReadOnly))

        for (device, source) in [(a, first), (b, second)] {
            let converted = try XCTUnwrap(result.devices.first { $0.id == device.id })
            guard case .managedImage(let image) = converted.backing else { return XCTFail("device wasn't converted") }

            var updated = model
            updated.configuration.hardware.storageDevices = result.devices
            let copyURL = updated.diskImageURL(for: image)

            XCTAssertTrue(copyURL.path.hasPrefix(model.bundleURL.path), "the copy must be inside the bundle")
            XCTAssertEqual(try Data(contentsOf: copyURL), try Data(contentsOf: source))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the source must not change")
        }

        /// The model's own configuration isn't changed until the caller applies the result.
        XCTAssertEqual(model.configuration.hardware.storageDevices, originalDevices)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).filter { $0.hasPrefix(".disk-copy") }, [])
    }

    func testFailedCopyLeavesConfigurationAndBundleUntouched() async throws {
        var model = try makeVirtualMachine()
        let first = try makeExternalImage(named: "Data.img", contents: "first")
        let missing = directoryURL.appending(path: "Missing.img")
        _ = addExternalDevice(first, to: &model)
        _ = addExternalDevice(missing, to: &model)

        let before = try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).sorted()

        do {
            _ = try await ExternalDiskImageCopier().copyExternalDiskImages(of: model)
            XCTFail("copying a missing image must fail")
        } catch { }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).sorted(), before, "copies made before the failure must be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testCopyFailureAtEveryStepLeavesBundleUntouched() async throws {
        var model = try makeVirtualMachine()
        let first = try makeExternalImage(named: "Data.img", contents: "first")
        let second = try makeExternalImage(named: "Other.dmg", contents: "second")
        _ = addExternalDevice(first, to: &model)
        _ = addExternalDevice(second, to: &model)

        let before = try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).sorted()

        let probe = FaultInjectingFileSystem()
        let result = try await ExternalDiskImageCopier(fileSystem: probe).copyExternalDiskImages(of: model)
        let operations = probe.operationCount
        result.discardCopies()

        for step in 1...operations {
            let fileSystem = FaultInjectingFileSystem()
            fileSystem.failingOperation = step

            do {
                _ = try await ExternalDiskImageCopier(fileSystem: fileSystem).copyExternalDiskImages(of: model)
                XCTFail("step \(step) should have failed")
            } catch { }

            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).sorted(), before, "step \(step)")
        }
    }

    func testDiscardingCopiesRemovesThem() async throws {
        var model = try makeVirtualMachine()
        _ = addExternalDevice(try makeExternalImage(named: "Data.img", contents: "first"), to: &model)

        let before = try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).sorted()

        let result = try await ExternalDiskImageCopier().copyExternalDiskImages(of: model)
        XCTAssertNotEqual(try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).sorted(), before)

        result.discardCopies()

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.bundleURL.path).sorted(), before)
    }

    // MARK: Eligibility

    func testEligibilityRequiresDisksOwnedByBundle() throws {
        var model = try makeVirtualMachine()
        model.metadata.installFinished = true

        XCTAssertFalse(SavedSessionEligibility.evaluate(model: model, options: .default).issues.contains { if case .externalDiskImage = $0 { true } else { false } })

        _ = addExternalDevice(try makeExternalImage(named: "Data.img", contents: "x"), to: &model)

        XCTAssertTrue(SavedSessionEligibility.evaluate(model: model, options: .default).issues.contains { if case .externalDiskImage = $0 { true } else { false } })
    }

    func testEligibilityExcludesSpecialBootModesAndOtherGuests() throws {
        let model = try makeVirtualMachine()

        for options in [VMSessionOptions(bootInRecoveryMode: true), VMSessionOptions(bootInDFUMode: true), VMSessionOptions(bootOnInstallDevice: true)] {
            XCTAssertTrue(SavedSessionEligibility.evaluate(model: model, options: options).issues.contains { if case .specialBootMode = $0 { true } else { false } })
        }

        var linux = model
        linux.configuration.systemType = .linux
        XCTAssertEqual(SavedSessionEligibility.evaluate(model: linux, options: .default).issues, [.unsupportedGuest])
    }

    func testRuntimeDescriptionDetectsTopologyChanges() {
        let a = SavedSessionRuntimeDescription(configuration: .init())

        let changed = VZVirtualMachineConfigurationForTests.make(cpuCount: 2)
        let b = SavedSessionRuntimeDescription(configuration: changed)

        XCTAssertNil(a.firstDifference(from: a))
        XCTAssertNotNil(a.firstDifference(from: b))
    }
}

import Virtualization

private enum VZVirtualMachineConfigurationForTests {
    static func make(cpuCount: Int) -> VZVirtualMachineConfiguration {
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = cpuCount
        return configuration
    }
}
