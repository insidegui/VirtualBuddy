import CryptoKit
import Foundation
import Security

public struct DeviceRegistrationError: LocalizedError, Sendable {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// A local login Keychain item per signing team. The creating application's Keychain ACL
/// protects the secret. Listing configured teams reads attributes only.
public actor DeviceRegistrationKeys {
    private let service: String

    public init(service: String) { self.service = service }

    private func query(_ team: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let team { query[kSecAttrAccount as String] = team }
        return query
    }

    public func teams() throws -> [String] {
        var query = query()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
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
        let item = RegistrationCredential(issuer: issuerID, keyID: keyID, secret: key.rawRepresentation)
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(item),
                                         kSecAttrLabel as String: "App Store Connect device registration (\(teamID))"]
        let match = query(teamID)
        let status = SecItemAdd(match.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try check(SecItemUpdate(match as CFDictionary, attributes as CFDictionary))
        } else {
            try check(status)
        }
    }

    public func remove(teamID: String) throws {
        let status = SecItemDelete(query(teamID) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    func credential(for team: String) throws -> RegistrationCredential {
        var query = query(team)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw DeviceRegistrationError("Add a team API key for \(team) in Developer settings.") }
        try check(status)
        guard let data = result as? Data else { throw DeviceRegistrationError("The stored API key could not be read.") }
        return try JSONDecoder().decode(RegistrationCredential.self, from: data)
    }

    private func check(_ status: OSStatus) throws {
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
