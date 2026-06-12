import Foundation

public struct KeychainPasswordItem: Sendable {
    // MARK: Types

    public enum KeychainError: Error, Sendable {
        case noPassword
        case unexpectedPasswordData
        case unexpectedItemData
        case unhandledError(status: OSStatus)
    }

    // MARK: Properties

    public let service: String

    public private(set) var account: String

    public let accessGroup: String?

    // MARK: Intialization

    public init(service: String, account: String, accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    // MARK: Keychain access

    public func readPassword() throws -> String {
        let data = try readData()
        return String(decoding: data, as: UTF8.self)
    }

    public func readData() throws -> Data {
        var query = KeychainPasswordItem.keychainQuery(withService: service, account: account, accessGroup: accessGroup)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = kCFBooleanTrue
        query[kSecReturnData as String] = kCFBooleanTrue

        var queryResult: AnyObject?
        let status = withUnsafeMutablePointer(to: &queryResult) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0))
        }

        guard status != errSecItemNotFound else { throw KeychainError.noPassword }
        guard status == noErr else { throw KeychainError.unhandledError(status: status) }

        guard let existingItem = queryResult as? [String: AnyObject],
              let passwordData = existingItem[kSecValueData as String] as? Data
        else {
            throw KeychainError.unexpectedPasswordData
        }

        return passwordData
    }

    public func savePassword(_ password: String) throws {
        try saveData(Data(password.utf8))
    }

    public func saveData(_ password: Data) throws {
        do {
            try _ = readData()

            var attributesToUpdate = [String: AnyObject]()
            attributesToUpdate[kSecValueData as String] = password as AnyObject?

            let query = KeychainPasswordItem.keychainQuery(withService: service, account: account, accessGroup: accessGroup)
            let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

            guard status == noErr else { throw KeychainError.unhandledError(status: status) }
        } catch KeychainError.noPassword {
            var newItem = KeychainPasswordItem.keychainQuery(withService: service, account: account, accessGroup: accessGroup)
            newItem[kSecValueData as String] = password as AnyObject?

            let status = SecItemAdd(newItem as CFDictionary, nil)

            guard status == noErr else { throw KeychainError.unhandledError(status: status) }
        }
    }

    public func deleteItem() throws {
        let query = KeychainPasswordItem.keychainQuery(withService: service, account: account, accessGroup: accessGroup)
        let status = SecItemDelete(query as CFDictionary)

        guard status == noErr || status == errSecItemNotFound else { throw KeychainError.unhandledError(status: status) }
    }

    // MARK: Convenience

    private static func keychainQuery(withService service: String, account: String? = nil, accessGroup: String? = nil) -> [String: AnyObject] {
        var query = [String: AnyObject]()
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrService as String] = service as AnyObject?

        if let account = account {
            query[kSecAttrAccount as String] = account as AnyObject?
        }

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup as AnyObject?
        }

        return query
    }
}
