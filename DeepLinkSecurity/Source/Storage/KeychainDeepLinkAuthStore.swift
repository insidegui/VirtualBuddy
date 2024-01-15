import Foundation
import Security
import OSLog
import CryptoKit

/// A robust auth store that uses signed keychain items for storing the user's authorization decisions.
public final actor KeychainDeepLinkAuthStore: DeepLinkAuthStore {

    private lazy var logger = Logger.deepLinkLogger(for: Self.self)

    private let namespace: String
    private let keyID: String

    public init(namespace: String, keyID: String) {
        self.namespace = namespace
        self.keyID = keyID
    }

    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    public func authorization(for client: DeepLinkClient) async -> DeepLinkClientAuthorization {
        do {
            guard let authData = try readKeychainItem(id: client.id) else {
                return .undetermined
            }

            do {
                /// Fetch the existing response item from the keychain.
                let response = try decoder.decode(KeychainAuthorizationResponse.self, from: authData)

                do {
                    /// The mere existence of the response in the keychain doesn't automatically mean the decision should be honored.
                    /// When written to the keychain, responses are signed with a private key.
                    /// When read from the keychain, the app verifies the stored signature against the corresponding public key,
                    /// ensuring that this response was written by an app that has permission to access this app's private key item from the keychain.
                    /// If another app attempts to write fake permissions to the keychain, they'll only be valid if the app can also sign the responses using our private key,
                    /// but in order to do that, the app would need the user's permission to access our keychain item, which triggers a permission prompt on macOS.
                    try validate(response: response)

                    logger.debug("Validated authorization response")

                    return response.authorization
                } catch {
                    logger.error("Failed to validate authorization response: \(error, privacy: .public)")

                    throw error
                }
            } catch {
                logger.fault("Error decoding authorization from Keychain entry: \(error, privacy: .public)")
                throw error
            }
        } catch {
            return .undetermined
        }
    }

    public func setAuthorization(_ authorization: DeepLinkClientAuthorization, for client: DeepLinkClient) async throws {
        let clientID = client.id

        let signingKey = try fetchSigningKey()
        let payload = KeychainAuthorizationResponse.signingPayload(clientID: clientID, authorization: authorization)
        let signature = try signingKey.sign(payload)

        let response = KeychainAuthorizationResponse(
            authorization: authorization,
            clientID: clientID,
            signingKeyID: keyID,
            signature: signature
        )

        guard let authData = try? encoder.encode(response) else {
            throw DeepLinkError("Failed to encode authorization")
        }

        try writeKeychainItem(id: clientID, data: authData)

        logger.debug("Stored authorization \(authorization) for \(client.designatedRequirement) (id = \(clientID, privacy: .public))")
    }

    private func validate(response: KeychainAuthorizationResponse) throws {
        let key = try fetchSigningKey()

        guard try key.verify(response.signature, for: response.signingPayload) else {
            throw DeepLinkError("Invalid authorization signature for client \(response.clientID)")
        }
    }

    private func fetchSigningKey() throws -> KeychainAuthorizationSigningKey {
        func createNewKey() throws -> KeychainAuthorizationSigningKey {
            logger.debug("Creating new authorization signing key")

            let newKey = KeychainAuthorizationSigningKey(id: keyID)

            let keyData = try encoder.encode(newKey)

            try writeKeychainItem(id: keyID, data: keyData)

            return newKey
        }

        if let data = try readKeychainItem(id: keyID) {
            logger.debug("Found existing authorization signing key")

            do {
                let key = try decoder.decode(KeychainAuthorizationSigningKey.self, from: data)

                return key
            } catch {
                logger.fault("Error reading existing authorization signing key, will generate new one. \(error, privacy: .public)")

                return try createNewKey()
            }
        } else {
            return try createNewKey()
        }
    }

    /// Simple helper for reading an item's data from the keychain.
    private func readKeychainItem(id: String) throws -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrService: namespace as CFString,
            kSecAttrAccount: id as CFString
        ] as [CFString: Any] as CFDictionary

        var result: CFTypeRef?
        let res = SecItemCopyMatching(query, &result)

        guard res != errSecItemNotFound else { return nil }

        try check(res)

        guard let data = result as? Data else {
            throw DeepLinkError("Failed to cast security query result to data")
        }

        return data
    }

    /// Simple helper for writing an item to the keychain.
    private func writeKeychainItem(id: String, data: Data) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace as CFString,
            kSecAttrAccount: id as CFString
        ] as [CFString: Any]

        var attrs = query
        attrs[kSecValueData] = data as CFData

        var result: CFTypeRef?
        var res = SecItemAdd(attrs as CFDictionary, &result)

        if res == errSecDuplicateItem {
            logger.debug("Keychain item \(id) already exists, updating")
            res = SecItemUpdate(query as CFDictionary, [kSecValueData: data as CFData] as CFDictionary)
        }

        try check(res)
    }

    /// Simple helper for removing an item from the keychain.
    private func deleteKeychainItem(id: String) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrService: namespace as CFString,
            kSecAttrAccount: id as CFString
        ] as [CFString: Any] as CFDictionary

        let res = SecItemDelete(query)
        
        guard res != errSecItemNotFound else { return }

        try check(res)
    }

}

/// This is the payload that's stored as the value for a keychain item representing the user's decision
/// regarding an app's permission to open deep links within this app.
private struct KeychainAuthorizationResponse: Codable {
    /// The user's decision (allow/deny).
    var authorization: DeepLinkClientAuthorization
    /// The SHA256 hash of the designated CS requirement for the app the decision is for.
    var clientID: String
    /// The identifier for the key used to generate the ECDSA signature.
    var signingKeyID: String
    /// The ECDSA signature for the payload, which is composed of the client ID and the user's decision.
    var signature: Data
}

private extension KeychainAuthorizationResponse {
    /// The payload that gets signed when storing the response on the keychain.
    var signingPayload: Data { Self.signingPayload(clientID: clientID, authorization: authorization) }

    static func signingPayload(clientID: String, authorization: DeepLinkClientAuthorization) -> Data {
        Data("\(clientID)-\(authorization.rawValue)".utf8)
    }
}

// MARK: - Crypto

private struct KeychainAuthorizationSigningKey: Codable {
    var id: String
    var keyData: Data
}

private extension KeychainAuthorizationSigningKey {
    init(id: String = UUID().uuidString) {
        let key = P521.Signing.PrivateKey()

        self.init(id: id, keyData: key.rawRepresentation)
    }
}

private extension KeychainAuthorizationSigningKey {
    var privateKey: P521.Signing.PrivateKey {
        get throws {
            try P521.Signing.PrivateKey(rawRepresentation: keyData)
        }
    }

    var publicKey: P521.Signing.PublicKey {
        get throws {
            try privateKey.publicKey
        }
    }
}

private extension KeychainAuthorizationSigningKey {
    func sign(_ digest: some DataProtocol) throws -> Data {
        try privateKey.signature(for: digest).rawRepresentation
    }

    func verify(_ signature: Data, for digest: some DataProtocol) throws -> Bool {
        let signature = try P521.Signing.ECDSASignature(rawRepresentation: signature)
        return try publicKey.isValidSignature(signature, for: digest)
    }
}

// MARK: - Helpers

private func check(_ res: OSStatus) throws {
    guard res != errSecSuccess else { return }

    if let str = SecCopyErrorMessageString(res, nil) {
        throw DeepLinkError("Security error code \(res): \"\(str)\"")
    } else {
        throw DeepLinkError("Security error code \(res)")
    }
}
