import Foundation
import Testing
import VirtualWormhole
@testable import VirtualCore

struct GuestSystemInformationStorageTests {
    @Test func reportsSurviveReopeningWithoutChangingConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Guest.vbvm")
        var vm = try VBVirtualMachine(bundleURL: url, isNewInstall: true)
        try vm.saveMetadata()
        let configuration = try Data(contentsOf: vm.metadataFileURL("Config.plist"))
        let metadata = try Data(contentsOf: vm.metadataFileURL("Metadata.plist"))
        let information = GuestSystemInformation(osVersion: "26.1", osBuild: "25B1", computerName: "Test Guest",
                                               sipDescription: "System Integrity Protection status: disabled.")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try vm.recordGuestSystemInformation(information, receivedAt: date)
        try vm.saveMetadata()
        let reopened = try VBVirtualMachine(bundleURL: url, createIfNeeded: false)
        #expect(reopened.guestSystemInformation?.information == information)
        #expect(reopened.guestSystemInformation?.receivedAt == date)
        #expect(try Data(contentsOf: vm.metadataFileURL("Config.plist")) == configuration)
        #expect(try Data(contentsOf: vm.metadataFileURL("Metadata.plist")) == metadata)

        var second = try VBVirtualMachine(bundleURL: root.appendingPathComponent("Other.vbvm"), isNewInstall: true)
        try second.saveMetadata()
        second.reloadGuestSystemInformation()
        #expect(second.guestSystemInformation == nil)
    }

    @Test func missingCorruptAndFutureReportsDoNotPreventLoading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var vm = try VBVirtualMachine(bundleURL: root.appendingPathComponent("Guest.vbvm"), isNewInstall: true)
        try vm.saveMetadata()
        #expect(try VBVirtualMachine(bundleURL: vm.bundleURL, createIfNeeded: false).guestSystemInformation == nil)
        try vm.write(Data("corrupt".utf8), forMetadataFileNamed: VBVirtualMachine.guestSystemInformationFileName)
        #expect(try VBVirtualMachine(bundleURL: vm.bundleURL, createIfNeeded: false).guestSystemInformation == nil)
        var future = VBGuestSystemInformation(receivedAt: .now, information: .init(osVersion: "future"))
        future.version = 2
        try vm.write(PropertyListEncoder().encode(future), forMetadataFileNamed: VBVirtualMachine.guestSystemInformationFileName)
        #expect(try VBVirtualMachine(bundleURL: vm.bundleURL, createIfNeeded: false).guestSystemInformation == nil)
        try vm.recordGuestSystemInformation(.init(osVersion: "26.0"))
        try vm.deleteMetadataFile(named: VBVirtualMachine.guestSystemInformationFileName)
        vm.reloadMetadata()
        #expect(vm.guestSystemInformation == nil)
    }
}
