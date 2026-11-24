import CryptoKit
import Foundation
import LocalAuthentication
import Security

public struct DeviceRegistrationError: LocalizedError, Sendable {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// One Keychain session of user presence. Using the same value for several reads asks the user once.
final class RegistrationAuthentication: @unchecked Sendable {
    let context = LAContext()
}

/// Each signing team's key is a data protection Keychain item that only this app's access
/// group can reach, and reading it requires Touch ID or the account password. A second item
/// without the secret marks the team as configured, so listing teams never asks the user.
public actor DeviceRegistrationKeys {
    private let service: String

    public init(service: String) { self.service = service }

    private static func query(_ service: String, team: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecUseDataProtectionKeychain as String: true]
        if let team { query[kSecAttrAccount as String] = team }
        return query
    }

    private var markers: String { service + ".teams" }

    public func teams() throws -> [String] {
        var query = Self.query(markers)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try Self.check(status)
        return ((result as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    public func save(teamID: String, issuerID: UUID, keyID: String, privateKeyFile: URL) throws {
        let validID = /^[A-Z0-9]{10}$/
        guard teamID.wholeMatch(of: validID) != nil, keyID.wholeMatch(of: validID) != nil else {
            throw DeviceRegistrationError("Enter the 10-character signing team ID and API key ID.")
        }
        let file = try FileHandle(forReadingFrom: privateKeyFile)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: 8193), data.count <= 8192,
              let pem = String(data: data, encoding: .utf8),
              let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
            throw DeviceRegistrationError("Choose the P-256 private key (.p8) downloaded from App Store Connect.")
        }
        var failure: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &failure) else {
            throw failure?.takeRetainedValue() as Error? ?? DeviceRegistrationError("Could not protect the API key.")
        }
        let item = RegistrationCredential(issuer: issuerID, keyID: keyID, secret: key.rawRepresentation)
        try replace(Self.query(service, team: teamID), with: [
            kSecValueData as String: try JSONEncoder().encode(item), kSecAttrAccessControl as String: access,
            kSecAttrLabel as String: "App Store Connect device registration (\(teamID))"
        ])
        try replace(Self.query(markers, team: teamID), with: [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrLabel as String: "App Store Connect device registration team (\(teamID))"
        ])
    }

    public func remove(teamID: String) throws {
        for service in [service, markers] {
            let status = SecItemDelete(Self.query(service, team: teamID) as CFDictionary)
            if status != errSecItemNotFound { try Self.check(status) }
        }
    }

    /// Updating a protected item would ask for the user's presence. Deleting it does not.
    private func replace(_ query: [String: Any], with attributes: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try Self.check(status) }
        try Self.check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
    }

    /// Waits for the user without holding the actor or a concurrency thread.
    nonisolated func credential(for team: String, reason: String, authentication: RegistrationAuthentication) async throws -> RegistrationCredential {
        let service = service
        let (status, data): (OSStatus, Data?) = await withCheckedContinuation { result in
            DispatchQueue.global(qos: .userInitiated).async {
                var query = Self.query(service, team: team)
                authentication.context.localizedReason = reason
                query[kSecUseAuthenticationContext as String] = authentication.context
                query[kSecReturnData as String] = true
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                result.resume(returning: (status, item as? Data))
            }
        }
        switch status {
        case errSecItemNotFound: throw DeviceRegistrationError("Add a team API key for \(team) in Developer settings.")
        case errSecUserCanceled: throw CancellationError()
        default: try Self.check(status)
        }
        guard let data else { throw DeviceRegistrationError("The stored API key could not be read.") }
        return try JSONDecoder().decode(RegistrationCredential.self, from: data)
    }

    private static func check(_ status: OSStatus) throws {
        guard status != errSecMissingEntitlement else {
            throw DeviceRegistrationError("This build cannot store team API keys because it is not signed with an application identifier. Register the Mac in Apple Developer instead.")
        }
        guard status == errSecSuccess else {
            throw DeviceRegistrationError(SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status).")
        }
    }
}

struct RegistrationCredential: Codable, Sendable {
    let issuer: UUID
    let keyID: String
    let secret: Data

    func token(at now: Date) throws -> String {
        func encode(_ bytes: Data) -> String {
            bytes.base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        let issued = Int(now.timeIntervalSince1970)
        let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "typ": "JWT", "kid": keyID])
        let claims = try JSONSerialization.data(withJSONObject: [
            "iss": issuer.uuidString.lowercased(), "iat": issued, "exp": issued + 300, "aud": "appstoreconnect-v1"
        ])
        let payload = encode(header) + "." + encode(claims)
        let key = try P256.Signing.PrivateKey(rawRepresentation: secret)
        return payload + "." + encode(try key.signature(for: Data(payload.utf8)).rawRepresentation)
    }
}
