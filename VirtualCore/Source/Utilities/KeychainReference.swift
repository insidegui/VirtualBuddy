import Foundation
import OSLog

/// A type that can be stored in an encodable parent that wants one of its properties to reference a Keychain item.
@propertyWrapper
public struct KeychainReference: Codable, Hashable, Sendable {
    private let logger = Logger(subsystem: "codes.rambo.VirtualCore", category: String(describing: KeychainReference.self))

    public var wrappedValue: String {
        get { read() ?? "" }
        nonmutating set {
            do {
                try write(newValue)
            } catch {
                logger.error("Error writing keychain item: \(error, privacy: .public)")
            }
        }
    }

    public var projectedValue: Self { self }

    public static let stringPrefix = "@@KEYCHAIN@@"

    private let keychainItem: KeychainPasswordItem

    public init(service: String, account: String) {
        self.keychainItem = KeychainPasswordItem(service: service, account: account)
    }

    private init(jsonRepresentation: JSONRepresentation) {
        self.init(
            service: jsonRepresentation.service,
            account: jsonRepresentation.account
        )
    }

    public func read() -> String? { try? keychainItem.readPassword() }

    public func write(_ password: String) throws {
        try keychainItem.savePassword(password)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public func encodableString() -> String {
        do {
            let jsonRep = jsonRepresentation()
            let json = try String(decoding: Self.encoder.encode(jsonRep), as: UTF8.self)
            return Self.stringPrefix + json
        } catch {
            preconditionFailure("Encoding a \(Self.self) should never fail. Error: \(error)")
        }
    }

    // MARK: - Encoding / Decoding

    private struct JSONRepresentation: Codable {
        let service: String
        let account: String
    }

    private func jsonRepresentation() -> JSONRepresentation {
        JSONRepresentation(
            service: keychainItem.service,
            account: keychainItem.account
        )
    }

    private init(encodedString: String) throws {
        guard encodedString.hasPrefix(Self.stringPrefix) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Encoded Keychain reference is missing \"\(Self.stringPrefix)\" prefix."))
        }

        let sanitized = encodedString.suffix(from: encodedString.index(encodedString.startIndex, offsetBy: Self.stringPrefix.count))

        let json = Data(sanitized.utf8)

        let jsonRep = try Self.decoder.decode(JSONRepresentation.self, from: json)

        self.init(jsonRepresentation: jsonRep)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        let string = try container.decode(String.self)

        try self.init(encodedString: string)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        let string = encodableString()

        try container.encode(string)
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        let value = read() ?? ""
        hasher.combine(value)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.read() == rhs.read()
    }
}
