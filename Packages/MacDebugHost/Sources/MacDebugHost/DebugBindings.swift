import CryptoKit
import Foundation
import MacDebugProtocol
import Security

/// A scheme the developer created in the host app for one destination.
/// Creating the scheme is the developer's approval for runs that carry its identifier.
public struct DebugBinding: Codable, Equatable, Sendable {
    public let id: UUID
    public let destination: UUID
    public let target: String

    public init(id: UUID, destination: UUID, target: String) {
        self.id = id
        self.destination = destination
        self.target = target
    }
}

/// The broker starts runs only for bindings found here, and takes the destination
/// from the stored record instead of from the process that requested the run.
public protocol DebugBindingStore: Sendable {
    func register(_ binding: DebugBinding) throws
    func binding(for id: UUID) throws -> DebugBinding?
}

/// Stores each binding in the login Keychain with an authentication code. Another
/// process running as the same user can add Keychain items, but it cannot read the
/// app's authentication key without the user's permission, so it cannot forge a record.
public final class KeychainDebugBindingStore: DebugBindingStore {
    private struct Record: Codable {
        let binding: DebugBinding
        let code: Data
    }

    private let service: String
    private static let keyAccount = "authentication-key"

    public init(service: String) { self.service = service }

    public func register(_ binding: DebugBinding) throws {
        let record = Record(binding: binding, code: Data(HMAC<SHA256>.authenticationCode(for: Self.payload(binding), using: try key())))
        try write(JSONEncoder().encode(record), account: binding.id.uuidString)
    }

    public func binding(for id: UUID) throws -> DebugBinding? {
        guard let data = try read(account: id.uuidString),
              let record = try? JSONDecoder().decode(Record.self, from: data), record.binding.id == id,
              HMAC<SHA256>.isValidAuthenticationCode(record.code, authenticating: Self.payload(record.binding), using: try key()) else {
            return nil
        }
        return record.binding
    }

    private static func payload(_ binding: DebugBinding) -> Data {
        Data([binding.id.uuidString, binding.destination.uuidString, binding.target].joined(separator: "\n").utf8)
    }

    private func key() throws -> SymmetricKey {
        if let data = try read(account: Self.keyAccount), data.count == SHA256.byteCount { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try write(key.withUnsafeBytes { Data($0) }, account: Self.keyAccount)
        return key
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func read(account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }

    /// Replaces any existing item so the new one carries this app's access control,
    /// including when another process created an item with the same name first.
    private func write(_ data: Data, account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
        var attributes = query(account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrLabel as String] = "Xcode debugging scheme approval"
        try check(SecItemAdd(attributes as CFDictionary, nil))
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw MacDebugError(SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status).")
        }
    }
}
