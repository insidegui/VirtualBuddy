import CryptoKit
import Foundation
import Testing
import VirtualWormhole
@testable import VirtualCore

/// Stands in for the host's Keychain, which a test bundle can't use.
private final class HostApprovals: @unchecked Sendable {
    private var digests: [String: Data] = [:]
    var store: SignedSettingApprovals {
        SignedSettingApprovals(digest: { self.digests[$0] }, record: { self.digests[$1] = $0 })
    }
}

struct ServiceTunnelSettingsTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = P256.Signing.PrivateKey()
    private let host = HostApprovals()
    private let rules = [ServiceTunnel(listensOnHost: false, listener: .tcp(8000), destination: .unix("/private/tmp/example.sock"))]

    private func withVM(_ body: (VBVirtualMachine) throws -> Void) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = try VBVirtualMachine(bundleURL: root.appendingPathComponent("Original.vbvm"), isNewInstall: true)
        try vm.saveMetadata()
        try body(vm)
    }

    private var setting: SignedVMSetting<[ServiceTunnel]> {
        VBVirtualMachine.tunnelSetting(key: { [key] _ in key }, approvals: host.store)
    }

    private func duplicate(_ original: VBVirtualMachine, named name: String = "Copy") throws -> VBVirtualMachine {
        let key = key, host = host
        return try VMBundleDuplicator { original, copy in
            try VBVirtualMachine.tunnelSetting(key: { _ in key }, approvals: host.store).carryApproval(from: original, to: copy)
        }.duplicate(bundleAt: original.bundleURL, to: root.appendingPathComponent("\(name).vbvm"))
    }

    @Test func libraryDuplicateIsApprovedAgainAndAnotherHostCanReapproveItsCopy() throws {
        let source = setting
        let otherKey = P256.Signing.PrivateKey()
        let destination = VBVirtualMachine.tunnelSetting(key: { _ in otherKey }, approvals: HostApprovals().store)
        try withVM { original in
            #expect(source.read(from: original) == .missing)
            try source.approve(rules, in: original)
            let copy = try duplicate(original)
            #expect(copy.uuid != original.uuid)
            #expect(try source.approvedValue(in: copy) == rules)
            #expect(try Data(contentsOf: copy.metadataFileURL(source.filename)) != Data(contentsOf: original.metadataFileURL(source.filename)))

            let imported = destination.read(from: copy)
            #expect(imported == .needsApproval(rules))
            #expect(try destination.approvedValue(in: copy) == nil)
            try destination.approve(try #require(imported.reviewValue), in: copy)
            #expect(destination.read(from: copy) == .approved(rules))
            #expect(source.read(from: copy) == .needsApproval(rules))
            #expect(source.read(from: original) == .approved(rules))
        }
    }

    @Test func libraryDuplicateOnlyCarriesWhatIsApprovedForTheOriginalRightNow() throws {
        let store = setting
        try withVM { original in
            try store.approve(rules, in: original)
            let url = original.metadataFileURL(store.filename)
            let approved = try Data(contentsOf: url)

            /// Signed with a key this host doesn't know, as in a bundle that came from somewhere else.
            let foreignKey = P256.Signing.PrivateKey()
            try VBVirtualMachine.tunnelSetting(key: { _ in foreignKey }, approvals: HostApprovals().store).approve(rules, in: original)
            #expect(store.read(from: try duplicate(original, named: "Foreign")) == .needsApproval(rules))

            /// A record that was approved here, but has since been replaced.
            try store.approve([], in: original)
            try approved.write(to: url, options: .atomic)
            #expect(store.read(from: try duplicate(original, named: "Replaced")) == .needsApproval(rules))
        }
    }

    @Test func bundleCopiedOutsideOfTheLibraryNeedsApproval() throws {
        let store = setting
        try withVM { original in
            try store.approve(rules, in: original)
            let copyURL = root.appendingPathComponent("Finder Copy.vbvm")
            try FileManager.default.copyItem(at: original.bundleURL, to: copyURL)
            let copy = try VBVirtualMachine(bundleURL: copyURL, isNewInstall: false, createIfNeeded: false)
            #expect(copy.uuid == original.uuid)
            #expect(store.read(from: copy) == .needsApproval(rules))
            #expect(try store.approvedValue(in: copy) == nil)
            #expect(store.read(from: original) == .approved(rules))

            try store.approve(rules, in: copy)
            #expect(store.read(from: copy) == .approved(rules))
            #expect(store.read(from: original) == .approved(rules))
        }
    }

    @Test func renamedBundleKeepsApproval() throws {
        let store = setting
        try withVM { original in
            try store.approve(rules, in: original)
            let renamedURL = root.appendingPathComponent("Renamed.vbvm")
            try FileManager.default.moveItem(at: original.bundleURL, to: renamedURL)
            let renamed = try VBVirtualMachine(bundleURL: renamedURL, isNewInstall: false, createIfNeeded: false)
            #expect(store.read(from: renamed) == .approved(rules))
        }
    }

    @Test func replacedRecordCannotBeBroughtBack() throws {
        let store = setting
        try withVM { vm in
            try store.approve(rules, in: vm)
            let url = vm.metadataFileURL(store.filename)
            let earlier = try Data(contentsOf: url)
            try store.approve([], in: vm)
            #expect(store.read(from: vm) == .approved([]))

            try earlier.write(to: url, options: .atomic)
            #expect(store.read(from: vm) == .needsApproval(rules))
            #expect(try store.approvedValue(in: vm) == nil)
        }
    }

    @Test func recordApprovedForOneVirtualMachineIsNotApprovedInAnother() throws {
        let store = setting
        try withVM { trusted in
            try store.approve(rules, in: trusted)
            let other = try VBVirtualMachine(bundleURL: root.appendingPathComponent("Other.vbvm"), isNewInstall: true)
            try other.saveMetadata()
            try store.approve([], in: other)

            let record = try Data(contentsOf: trusted.metadataFileURL(store.filename))
            try record.write(to: other.metadataFileURL(store.filename), options: .atomic)
            #expect(store.read(from: other) == .needsApproval(rules))
            #expect(try store.approvedValue(in: other) == nil)
        }
    }

    @Test func editsMissingTagsAndMalformedRecordsCannotAuthorizeTunnels() throws {
        let store = setting
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
        let store = setting
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
        let first = SignedVMSetting<String>("Example", schema: 1, key: { _ in key }, approvals: host.store, validate: { _ in })
        let second = SignedVMSetting<String>("Other", schema: 1, key: { _ in key }, approvals: host.store, validate: { _ in })
        let newer = SignedVMSetting<String>("Example", schema: 2, key: { _ in key }, approvals: host.store, validate: { _ in })
        let noKey = SignedVMSetting<String>("Example", schema: 1, key: { access in
            #expect(access == .verify)
            return nil
        }, approvals: host.store, validate: { _ in })
        let locked = SignedVMSetting<String>("Example", schema: 1, key: { _ in throw Failure("Keychain unavailable") }, approvals: host.store, validate: { _ in })
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
