import Foundation
import LocalAuthentication
import Security

/// Remembers which signed record the host last approved, in the host app's Keychain rather than in any bundle.
///
/// A signature alone stays valid forever, so a bundle could bring back a record the user has since replaced.
/// Only the record whose digest is stored here counts as approved.
struct HostSettingsApprovalStore {
    var service = "codes.rambo.VirtualBuddy.signed-settings.approvals"

    private func item(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func digest(for account: String) throws -> Data? {
        var query = item(account)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let digest = result as? Data else { throw Failure("The saved settings approval is invalid.") }
        return digest
    }

    func record(_ digest: Data, for account: String) throws {
        let value = [kSecValueData as String: digest]
        var status = SecItemUpdate(item(account) as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var new = item(account)
            new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            new[kSecAttrLabel as String] = "VirtualBuddy settings approval"
            new[kSecValueData as String] = digest
            status = SecItemAdd(new as CFDictionary, nil)
            // A concurrent approval of the same bundle added the item first. The latest approval wins.
            if status == errSecDuplicateItem {
                status = SecItemUpdate(item(account) as CFDictionary, value as CFDictionary)
            }
        }
        try check(status)
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw Failure("Unable to access the saved settings approval. \(detail)")
        }
    }
}
