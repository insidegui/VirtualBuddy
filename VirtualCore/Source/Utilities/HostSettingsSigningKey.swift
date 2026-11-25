import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// A per-user, device-local key in the host app's default Keychain access group.
struct HostSettingsSigningKey {
    enum Access { case verify, sign }

    var service = "codes.rambo.VirtualBuddy.signed-settings"

    func key(for access: Access) throws -> P256.Signing.PrivateKey? {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "P256-Signing-v1"
        ]

        func read() throws -> P256.Signing.PrivateKey? {
            var query = identity
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try check(status)
            guard let bytes = result as? Data, let privateKey = try? P256.Signing.PrivateKey(rawRepresentation: bytes) else {
                throw Failure("The host settings signing key is invalid.")
            }
            return privateKey
        }

        if let existing = try read() { return existing }
        guard access == .sign else { return nil }

        let newKey = P256.Signing.PrivateKey()
        var item = identity
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "VirtualBuddy settings signing key"
        item[kSecValueData as String] = newKey.rawRepresentation
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // A concurrent first approval won the insert. Never replace its key.
            guard let existing = try read() else { throw Failure("The host settings signing key disappeared.") }
            return existing
        }
        try check(status)
        return newKey
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw Failure("Unable to access the host settings signing key. \(detail)")
        }
    }
}
