//
//  DiskResizeSupportTests.swift
//  VirtualWormholeTests
//

import XCTest
@testable import VirtualCore

final class DiskResizeSupportTests: XCTestCase {

    func testLegacyManagedImageHasNoPendingResize() throws {
        let data = Data(#"{"id":"disk","filename":"Disk","size":1024,"format":0}"#.utf8)
        let image = try JSONDecoder().decode(VBManagedDiskImage.self, from: data)
        XCTAssertFalse(image.resizePending)
    }

    func testPendingResizeRoundTrips() throws {
        var image = VBManagedDiskImage(id: "disk", filename: "Disk", size: 1024, format: .raw)
        image.resizePending = true

        let data = try PropertyListEncoder().encode(image)
        let decoded = try PropertyListDecoder().decode(VBManagedDiskImage.self, from: data)

        XCTAssertTrue(decoded.resizePending)
    }

    @MainActor
    func testNormalLaunchDoesNotInspectDiskImages() async throws {
        var vm = try makeVM(format: .sparse, resizePending: false)
        let image = try managedImage(from: vm)
        try Data().write(to: vm.diskImageURL(for: image))

        let didResize = try await vm.checkAndResizeDiskImages()
        XCTAssertFalse(didResize)
    }

    @MainActor
    func testFailedResizeKeepsPendingRequest() async throws {
        var vm = try makeVM(format: .sparse, resizePending: true)
        let image = try managedImage(from: vm)
        try Data().write(to: vm.diskImageURL(for: image))

        do {
            _ = try await vm.checkAndResizeDiskImages()
            XCTFail("Expected invalid sparse image resize to fail")
        } catch {
            XCTAssertTrue(try managedImage(from: vm).resizePending)
        }
    }

    @MainActor
    func testSatisfiedResizeClearsPendingRequest() async throws {
        var vm = try makeVM(format: .raw, resizePending: true)
        let image = try managedImage(from: vm)
        try Data(count: 4096).write(to: vm.diskImageURL(for: image))

        let didResize = try await vm.checkAndResizeDiskImages()
        XCTAssertFalse(didResize)
        XCTAssertFalse(try managedImage(from: vm).resizePending)
    }

    private func makeVM(
        format: VBManagedDiskImage.Format,
        resizePending: Bool
    ) throws -> VBVirtualMachine {
        let bundleURL = temporaryURL().appendingPathExtension(VBVirtualMachine.bundleExtension)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundleURL) }

        var vm = try VBVirtualMachine(bundleURL: bundleURL, isNewInstall: true)
        var image = VBManagedDiskImage(id: "disk", filename: "Disk", size: 2048, format: format)
        image.resizePending = resizePending
        vm.configuration.hardware.storageDevices = [
            VBStorageDevice(
                id: "boot",
                isBootVolume: true,
                isReadOnly: false,
                isUSBMassStorageDevice: false,
                backing: .managedImage(image)
            )
        ]
        return vm
    }

    private func managedImage(from vm: VBVirtualMachine) throws -> VBManagedDiskImage {
        let device = try XCTUnwrap(vm.configuration.hardware.storageDevices.first)
        guard case .managedImage(let image) = device.backing else {
            return try XCTUnwrap(nil)
        }
        return image
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}
