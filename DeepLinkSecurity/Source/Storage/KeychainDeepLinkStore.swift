import Cocoa
import LocalAuthentication
import OSLog
import Security

/// The stores that held deep link clients and decisions before ``KeychainDeepLinkStore``.
public struct LegacyDeepLinkStores {
    let authStore: DeepLinkAuthStore
    let managementStore: UserDefaultsDeepLinkManagementStore

    public init(authStore: DeepLinkAuthStore, managementStore: UserDefaultsDeepLinkManagementStore) {
        self.authStore = authStore
        self.managementStore = managementStore
    }
}

/// Keeps both the clients that asked to open deep links and the user's decision about each of them
/// in device-local Keychain records that only the app itself can read or write.
///
/// Nothing shown to the user or used for a decision comes from preferences or files that other
/// processes can edit. What a record says about a client's name and icon is looked up from the
/// client itself whenever it's listed.
public final actor KeychainDeepLinkStore: DeepLinkAuthStore, DeepLinkManagementStore {
    private struct Record: Codable {
        var url: URL
        var bundleIdentifier: String?
        var displayName: String
        var authorization: DeepLinkClientAuthorization
    }

    private let logger = Logger.deepLinkLogger(for: KeychainDeepLinkStore.self)
    private let clients: KeychainRecords
    private let state: KeychainRecords
    private let legacy: LegacyDeepLinkStores?
    private var migration: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<[DeepLinkClientDescriptor]>.Continuation] = [:]

    private static let migrationMarker = "MigratedLegacyStores"

    /// - Parameters:
    ///   - service: Names the Keychain records. Use a different one for each independent set of clients.
    ///   - legacy: Where clients and decisions were kept before, to bring them over once.
    public init(service: String, legacy: LegacyDeepLinkStores? = nil) {
        clients = KeychainRecords(service: "\(service).clients", label: "Deep link client")
        state = KeychainRecords(service: "\(service).state", label: "Deep link storage state")
        self.legacy = legacy
    }

    // MARK: Decisions

    public func authorization(for client: DeepLinkClient) async -> DeepLinkClientAuthorization {
        await migrateIfNeeded()
        do {
            return try record(for: client.id)?.authorization ?? .undetermined
        } catch {
            logger.error("Unable to read the decision for \(client.id, privacy: .public): \(error, privacy: .public)")
            return .undetermined
        }
    }

    public func setAuthorization(_ authorization: DeepLinkClientAuthorization, for client: DeepLinkClient) async throws {
        await migrateIfNeeded()
        try save(authorization, for: client)
        publish()
    }

    private func save(_ authorization: DeepLinkClientAuthorization, for client: DeepLinkClient) throws {
        let descriptor = DeepLinkClientDescriptor(client: client)
        try save(Record(
            url: client.url,
            bundleIdentifier: descriptor.bundleIdentifier,
            displayName: descriptor.displayName,
            authorization: authorization
        ), for: client.id)
    }

    // MARK: Clients

    public nonisolated var currentClientDescriptors: [DeepLinkClientDescriptor] {
        do {
            return try clients.all().compactMap { id, data in
                guard let record = try? PropertyListDecoder().decode(Record.self, from: data) else { return nil }
                return Self.descriptor(id: id, record: record)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        } catch {
            logger.error("Unable to list deep link clients: \(error, privacy: .public)")
            return []
        }
    }

    public nonisolated func clientDescriptors() -> AsyncStream<[DeepLinkClientDescriptor]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: [DeepLinkClientDescriptor].self, bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        Task { await subscribe(id, continuation) }
        return stream
    }

    public func hasDescriptor(with id: DeepLinkClientDescriptor.ID) async -> Bool {
        await migrateIfNeeded()
        return (try? record(for: id)) != nil
    }

    /// Adds a client that has no decision yet, or refreshes what's known about one that's already there.
    /// The decision only ever changes through ``setAuthorization(_:for:)``, whatever the descriptor says.
    public func insert(_ descriptor: DeepLinkClientDescriptor) async throws {
        await migrateIfNeeded()
        try save(Record(
            url: descriptor.url,
            bundleIdentifier: descriptor.bundleIdentifier,
            displayName: descriptor.displayName,
            authorization: try record(for: descriptor.id)?.authorization ?? .undetermined
        ), for: descriptor.id)
        publish()
    }

    /// Forgets the client along with the decision about it, so that it has to ask again.
    public func delete(_ descriptor: DeepLinkClientDescriptor) async throws {
        await migrateIfNeeded()
        try clients.remove(descriptor.id)
        publish()
    }

    private func record(for id: String) throws -> Record? {
        guard let data = try clients.data(for: id) else { return nil }
        return try PropertyListDecoder().decode(Record.self, from: data)
    }

    private func save(_ record: Record, for id: String) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try clients.set(try encoder.encode(record), for: id)
    }

    private static func descriptor(id: String, record: Record) -> DeepLinkClientDescriptor {
        var url = record.url
        if !FileManager.default.fileExists(atPath: url.path), let bundleIdentifier = record.bundleIdentifier,
           let moved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            url = moved
        }
        var descriptor = DeepLinkClientDescriptor(clientID: id, clientURL: url, authorization: record.authorization)
        if !descriptor.isValid {
            descriptor.bundleIdentifier = record.bundleIdentifier
            descriptor.displayName = record.displayName
        }
        return descriptor
    }

    // MARK: Changes

    private func subscribe(_ id: UUID, _ continuation: AsyncStream<[DeepLinkClientDescriptor]>.Continuation) async {
        await migrateIfNeeded()
        subscribers[id] = continuation
        continuation.yield(currentClientDescriptors)
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func publish() {
        guard !subscribers.isEmpty else { return }
        let descriptors = currentClientDescriptors
        for continuation in subscribers.values { continuation.yield(descriptors) }
    }

    // MARK: Migration

    private func migrateIfNeeded() async {
        guard let legacy else { return }
        if migration == nil {
            migration = Task { await self.migrate(from: legacy) }
        }
        await migration?.value
    }

    /// Brings over the clients whose decision the previous stores still vouch for, once.
    ///
    /// The previous list was kept in preferences, where anything could have edited it. An entry only counts
    /// if the app found where it points is the one the entry names, and the decision is the one the previous
    /// Keychain store returns for that app. Entries without a decision are dropped: those apps ask again.
    private func migrate(from legacy: LegacyDeepLinkStores) async {
        do {
            guard try state.data(for: Self.migrationMarker) == nil else { return }
            var migrated = 0
            for descriptor in legacy.managementStore.currentClientDescriptors {
                guard let client = try? DeepLinkClient(url: descriptor.url), client.id == descriptor.id else {
                    logger.warning("Not keeping \(descriptor.id, privacy: .public): it's no longer the app at its saved location")
                    continue
                }
                let authorization = await legacy.authStore.authorization(for: client)
                guard authorization != .undetermined else { continue }
                // A decision made since the update wins over the one being brought over.
                guard try record(for: client.id) == nil else { continue }
                try save(authorization, for: client)
                migrated += 1
            }
            try state.set(Data(), for: Self.migrationMarker)
            // The previous decisions stay in the Keychain, where an earlier version of the app still finds them.
            await legacy.managementStore.removeAll()
            logger.notice("Migrated \(migrated, privacy: .public) deep link client(s)")
        } catch {
            // Nothing is marked as done, so this runs again the next time the app starts.
            logger.error("Unable to migrate deep link clients: \(error, privacy: .public)")
        }
    }
}

/// Device-local records in the app's default Keychain access group, which only code signed as the app can use.
private struct KeychainRecords: Sendable {
    let service: String
    let label: String

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
        guard let data = result as? Data else { throw DeepLinkError("A saved deep link record is invalid.") }
        return data
    }

    func all() throws -> [(account: String, data: Data)] {
        var query = reading(items)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        return (result as? [[String: Any]] ?? []).compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String, let data = item[kSecValueData as String] as? Data else { return nil }
            return (account, data)
        }
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
            if status == errSecDuplicateItem {
                status = SecItemUpdate(item(account) as CFDictionary, value as CFDictionary)
            }
        }
        try check(status)
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(item(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw DeepLinkError("Unable to access saved deep link records. \(detail)")
        }
    }
}
