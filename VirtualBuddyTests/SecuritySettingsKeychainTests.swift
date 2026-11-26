import Foundation
import Security
import Testing
@testable import VirtualCore

struct SecuritySettingsKeychainTests {
    private func items(in service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service
        ]
    }

    @Test
    func recordsAreDeviceOnlyKeychainItemsThatCanBeCountedAndRemovedTogether() throws {
        let service = "codes.rambo.VirtualBuddy.tests.security-settings.\(UUID().uuidString)"
        let records = SecurityKeychainRecords(service: service, label: "VirtualBuddy test record")
        defer { SecItemDelete(items(in: service) as CFDictionary) }

        #expect(try records.data(for: "first") == nil)
        #expect(try records.count() == 0)
        try records.removeAll()

        try records.set(Data([1]), for: "first")
        try records.set(Data(), for: "second")
        try records.set(Data([3]), for: "first")
        #expect(try records.data(for: "first") == Data([3]))
        #expect(try records.data(for: "second") == Data())
        #expect(try records.count() == 2)

        var query = items(in: service)
        query[kSecAttrAccount as String] = "first"
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        try #require(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool != true)

        try records.removeAll()
        #expect(try records.count() == 0)
        #expect(try records.data(for: "first") == nil)
    }
}
