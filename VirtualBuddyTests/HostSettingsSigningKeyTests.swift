import CryptoKit
import Foundation
import Security
import Testing
@testable import VirtualCore

struct HostSettingsSigningKeyTests {
    @Test
    func firstApprovalCreatesOneDeviceOnlyKeyInTheDataProtectionKeychain() async throws {
        let service = "codes.rambo.VirtualBuddy.tests.signed-settings.\(UUID().uuidString)"
        let store = HostSettingsSigningKey(service: service)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service
        ]
        defer { SecItemDelete(identity as CFDictionary) }
        #expect(try store.key(for: .verify) == nil)

        let publicKeys = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    let key = try #require(try store.key(for: .sign))
                    return key.publicKey.rawRepresentation
                }
            }
            var keys = Set<Data>()
            for try await key in group { keys.insert(key) }
            return keys
        }
        #expect(publicKeys.count == 1)
        let stored = try #require(try store.key(for: .verify))
        #expect(publicKeys.contains(stored.publicKey.rawRepresentation))

        var query = identity
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        try #require(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool != true)
    }

    @Test
    func approvalDigestsAreKeptPerAccountAndReplacedByTheLatestApproval() throws {
        let service = "codes.rambo.VirtualBuddy.tests.signed-settings.approvals.\(UUID().uuidString)"
        let store = HostSettingsApprovalStore(service: service)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service
        ]
        defer { SecItemDelete(identity as CFDictionary) }
        #expect(try store.digest(for: "first") == nil)

        try store.record(Data([1]), for: "first")
        try store.record(Data([2]), for: "second")
        try store.record(Data([3]), for: "first")
        #expect(try store.digest(for: "first") == Data([3]))
        #expect(try store.digest(for: "second") == Data([2]))

        var query = identity
        query[kSecAttrAccount as String] = "first"
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        try #require(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool != true)
    }
}
