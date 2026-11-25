import CryptoKit
import Foundation
import Testing
import VirtualWormhole
@testable import VirtualCore

struct ServiceTunnelSettingsTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = P256.Signing.PrivateKey()
    private let rules = [ServiceTunnel(listensOnHost: false, listener: .tcp(8000), destination: .unix("/private/tmp/example.sock"))]

    private func withVM(_ body: (VBVirtualMachine) throws -> Void) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = try VBVirtualMachine(bundleURL: root.appendingPathComponent("Original.vbvm"), isNewInstall: true)
        try vm.saveMetadata()
        try body(vm)
    }

    @Test func libraryDuplicateKeepsApprovalAndAnotherHostCanReapproveItsCopy() throws {
        let source = VBVirtualMachine.tunnelSetting { _ in key }
        let otherKey = P256.Signing.PrivateKey()
        let destination = VBVirtualMachine.tunnelSetting { _ in otherKey }
        try withVM { original in
            #expect(source.read(from: original) == .missing)
            try source.approve(rules, in: original)
            let copy = try VMBundleDuplicator().duplicate(bundleAt: original.bundleURL, to: root.appendingPathComponent("Copy.vbvm"))
            #expect(copy.uuid != original.uuid)
            #expect(try source.approvedValue(in: copy) == rules)
            #expect(try Data(contentsOf: copy.metadataFileURL(source.filename)) == Data(contentsOf: original.metadataFileURL(source.filename)))

            let imported = destination.read(from: copy)
            #expect(imported == .needsApproval(rules))
            #expect(try destination.approvedValue(in: copy) == nil)
            try destination.approve(try #require(imported.reviewValue), in: copy)
            #expect(destination.read(from: copy) == .approved(rules))
            #expect(source.read(from: copy) == .needsApproval(rules))
            #expect(source.read(from: original) == .approved(rules))
        }
    }

    @Test func editsMissingTagsAndMalformedRecordsCannotAuthorizeTunnels() throws {
        let store = VBVirtualMachine.tunnelSetting { _ in key }
        try withVM { vm in
            try store.approve(rules, in: vm)
            let url = vm.metadataFileURL(store.filename)
            let data = try Data(contentsOf: url)
            var record = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            var edited = rules
            edited[0].isEnabled.toggle()
            record["payload"] = try PropertyListEncoder().encode(["value": edited])
            func writeRecord() throws {
                try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0).write(to: url, options: .atomic)
            }
            try writeRecord()
            #expect(store.read(from: vm) == .needsApproval(edited))
            record.removeValue(forKey: "signature")
            try writeRecord()
            #expect(store.read(from: vm) == .needsApproval(edited))
            record["version"] = 2
            try writeRecord()
            if case .unavailable = store.read(from: vm) {} else { Issue.record("Accepted unknown format") }
            try Data([0]).write(to: url)
            if case .unavailable = store.read(from: vm) {} else { Issue.record("Accepted corrupt record") }
            let invalid = ServiceTunnel(listensOnHost: true, listener: .tcp(0), destination: .tcp(80))
            #expect(throws: (any Error).self) { try store.approve([invalid], in: vm) }
            #expect(try Data(contentsOf: url) == Data([0]))
        }
    }

    @Test func symbolicLinksCannotRedirectRecordReadsOrWrites() throws {
        let store = VBVirtualMachine.tunnelSetting { _ in key }
        try withVM { vm in
            try store.approve(rules, in: vm)
            let record = vm.metadataFileURL(store.filename)
            let outside = root.appendingPathComponent("outside.plist")
            try FileManager.default.moveItem(at: record, to: outside)
            let original = try Data(contentsOf: outside)
            try FileManager.default.createSymbolicLink(at: record, withDestinationURL: outside)
            #expect(store.read(from: vm).approvedValue == nil)
            try store.approve([], in: vm)
            #expect(store.read(from: vm) == .approved([]))
            #expect(try Data(contentsOf: outside) == original)
            let moved = root.appendingPathComponent("data")
            try FileManager.default.moveItem(at: vm.metadataDirectoryURL, to: moved)
            try FileManager.default.createSymbolicLink(at: vm.metadataDirectoryURL, withDestinationURL: moved)
            #expect(store.read(from: vm).approvedValue == nil)
            #expect(throws: (any Error).self) { try store.approve(rules, in: vm) }
        }
    }

    @Test func approvalIsScopedToFeatureAndSchemaAndVerificationNeverCreatesAKey() throws {
        let first = SignedVMSetting<String>("Example", schema: 1, key: { _ in key }, validate: { _ in })
        let second = SignedVMSetting<String>("Other", schema: 1, key: { _ in key }, validate: { _ in })
        let newer = SignedVMSetting<String>("Example", schema: 2, key: { _ in key }, validate: { _ in })
        let noKey = SignedVMSetting<String>("Example", schema: 1, key: { access in
            #expect(access == .verify)
            return nil
        }, validate: { _ in })
        let locked = SignedVMSetting<String>("Example", schema: 1, key: { _ in throw Failure("Keychain unavailable") }, validate: { _ in })
        try withVM { vm in
            try first.approve("value", in: vm)
            try FileManager.default.copyItem(at: vm.metadataFileURL(first.filename), to: vm.metadataFileURL(second.filename))
            #expect(second.read(from: vm) == .needsApproval("value"))
            if case .unavailable = newer.read(from: vm) {} else { Issue.record("Accepted incompatible schema") }
            #expect(noKey.read(from: vm) == .needsApproval("value"))
            #expect(locked.read(from: vm) == .unavailable("Keychain unavailable"))
            #expect(throws: (any Error).self) { try locked.approve("changed", in: vm) }
            #expect(first.read(from: vm) == .approved("value"))
        }
    }
}
