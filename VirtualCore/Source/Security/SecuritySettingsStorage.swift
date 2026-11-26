import CryptoKit
import Foundation
import LocalAuthentication
import Security
import VirtualWormhole

/// Device-local records in the host app's default Keychain access group.
///
/// Only code signed as the host app can read or write them, which is what keeps security settings
/// out of reach of anything that can merely write the app's preferences or files.
struct SecurityKeychainRecords {
    var service: String
    var label: String

    private var items: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: service
        ]
    }

    private func item(_ account: String) -> [String: Any] {
        var item = items
        item[kSecAttrAccount as String] = account
        return item
    }

    private func reading(_ query: [String: Any]) -> [String: Any] {
        var query = query
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    func data(for account: String) throws -> Data? {
        var query = reading(item(account))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw Failure("A saved security setting is invalid.") }
        return data
    }

    func set(_ data: Data, for account: String) throws {
        let value = [kSecValueData as String: data]
        var status = SecItemUpdate(item(account) as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var new = item(account)
            new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            new[kSecAttrLabel as String] = label
            new[kSecValueData as String] = data
            status = SecItemAdd(new as CFDictionary, nil)
            // Something else saved the same record first. The latest value wins.
            if status == errSecDuplicateItem {
                status = SecItemUpdate(item(account) as CFDictionary, value as CFDictionary)
            }
        }
        try check(status)
    }

    func count() throws -> Int {
        var query = reading(items)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return 0 }
        try check(status)
        return (result as? [Any])?.count ?? 0
    }

    func removeAll() throws {
        let status = SecItemDelete(items as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw Failure("Unable to access the saved security settings. \(detail)")
        }
    }
}

/// Where the host keeps its security settings.
///
/// Reading is open to any code in the host app. Changing a setting goes through
/// ``SecuritySettingsSession``, which requires the user to be present.
struct SecuritySettingsStorage {
    var savedLevel: () throws -> Data?
    var saveLevel: (Data) throws -> Void
    var hasRememberedTunnel: (_ key: String) throws -> Bool
    var rememberTunnel: (_ key: String) throws -> Void
    var rememberedTunnelCount: () throws -> Int
    var forgetTunnels: () throws -> Void

    static var keychain: Self {
        let settings = SecurityKeychainRecords(
            service: "codes.rambo.VirtualBuddy.security-settings",
            label: "VirtualBuddy security setting"
        )
        let tunnels = SecurityKeychainRecords(
            service: "codes.rambo.VirtualBuddy.remembered-service-tunnels",
            label: "VirtualBuddy reviewed service tunnel"
        )
        let levelAccount = "ServiceTunnelReview"
        return Self(
            savedLevel: { try settings.data(for: levelAccount) },
            saveLevel: { try settings.set($0, for: levelAccount) },
            hasRememberedTunnel: { try tunnels.data(for: $0) != nil },
            rememberTunnel: { try tunnels.set(Data(), for: $0) },
            rememberedTunnelCount: tunnels.count,
            forgetTunnels: tunnels.removeAll
        )
    }

    #if DEBUG
    /// Keeps settings for as long as the process runs, for tests and previews that can't use the Keychain.
    static func inMemory() -> Self {
        final class Values: @unchecked Sendable {
            let lock = NSLock()
            var level: Data?
            var tunnels = Set<String>()
        }
        let values = Values()
        return Self(
            savedLevel: { values.lock.withLock { values.level } },
            saveLevel: { level in values.lock.withLock { values.level = level } },
            hasRememberedTunnel: { key in values.lock.withLock { values.tunnels.contains(key) } },
            rememberTunnel: { key in values.lock.withLock { _ = values.tunnels.insert(key) } },
            rememberedTunnelCount: { values.lock.withLock { values.tunnels.count } },
            forgetTunnels: { values.lock.withLock { values.tunnels.removeAll() } }
        )
    }
    #endif

    /// The level the user chose. Anything short of a level that was read back intact is the strictest one.
    func tunnelLevel() -> ServiceTunnelSecurityLevel {
        do {
            guard let data = try savedLevel() else { return .strictest }
            guard let text = String(data: data, encoding: .utf8), let level = ServiceTunnelSecurityLevel(rawValue: text) else {
                SecuritySettingsLog.logger.error("The saved service tunnel review level is not valid. Every change is reviewed.")
                return .strictest
            }
            return level
        } catch {
            SecuritySettingsLog.logger.error("Unable to read the service tunnel review level, so every change is reviewed: \(error.localizedDescription, privacy: .public)")
            return .strictest
        }
    }

    func setTunnelLevel(_ level: ServiceTunnelSecurityLevel) throws {
        try saveLevel(Data(level.rawValue.utf8))
    }

    private func key(for identity: ServiceTunnelIdentity) -> String {
        let side = identity.listensOnHost ? "listen" : "connect"
        let digest = SHA256.hash(data: Data("\(side)\0\(identity.hostEndpoint.address)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func isRemembered(_ identity: ServiceTunnelIdentity) throws -> Bool {
        try hasRememberedTunnel(key(for: identity))
    }

    func remember(_ identities: some Sequence<ServiceTunnelIdentity>) throws {
        for identity in Set(identities) { try rememberTunnel(key(for: identity)) }
    }
}
