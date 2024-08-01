import Foundation
import OSLog

/// A management store that persists client descriptors in `UserDefaults`.
public final actor UserDefaultsDeepLinkManagementStore: DeepLinkManagementStore {
    nonisolated private lazy var logger = Logger.deepLinkLogger(for: Self.self)

    private let defaults: UserDefaults
    private let storageKey: String

    public init(namespace: String = "DeepLinkSecurity", suiteName: String? = nil, inMemory: Bool = false) {
        self.storageKey = "\(namespace)-Management"

        if let suiteName {
            if let instance = UserDefaults(suiteName: suiteName) {
                self.defaults = instance
            } else {
                assertionFailure("Failed to initialize user defaults with suite name \"\(suiteName)\"")
                self.defaults = .standard
            }
        } else if inMemory {
            self.defaults = UserDefaults()
        } else {
            self.defaults = .standard
        }

        Task {
            let existingDescriptors = readDescriptors()
            await cacheDescriptors(existingDescriptors)
        }
    }

    public func hasDescriptor(with id: DeepLinkClientDescriptor.ID) -> Bool { cachedDescriptors[id] != nil }

    public nonisolated func clientDescriptors() -> AsyncStream<[DeepLinkClientDescriptor]> {
        let stream = AsyncStream { [weak self] continuation in
            guard let self = self else { return }

            Task {
                await self.onStoreChanged { descriptorsByID in
                    let descriptors = descriptorsByID
                        .values
                        .map { $0.resolved() }
                        .sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending })

                    continuation.yield(descriptors)
                }
            }
        }

        Task {
            let snapshot = readDescriptors()
            await storeChangeHandler(snapshot)
        }

        return stream
    }

    public func insert(_ descriptor: DeepLinkClientDescriptor) async throws {
        await update(id: descriptor.id, with: descriptor)

        cacheDescriptors(readDescriptors())
    }
    
    public func delete(_ descriptor: DeepLinkClientDescriptor) async throws {
        await update(id: descriptor.id, with: nil)

        cacheDescriptors(readDescriptors())
    }

    private var cachedDescriptors = DescriptorStorage()

    private var storeChangeHandler: (DescriptorStorage) async -> Void = { _ in }

    private func onStoreChanged(perform block: @escaping (DescriptorStorage) async -> Void) {
        storeChangeHandler = block
    }

    private func cacheDescriptors(_ descriptors: DescriptorStorage) {
        self.cachedDescriptors = descriptors
    }

    private func update(id: DeepLinkClientDescriptor.ID, with descriptor: DeepLinkClientDescriptor?) async {
        do {
            var snapshot = readDescriptors()

            snapshot[id] = descriptor

            let data = try encoder.encode(snapshot)

            defaults.set(data, forKey: storageKey)
            defaults.synchronize()

            if let descriptor {
                logger.debug("Inserted descriptor \(descriptor.id, privacy: .public)")
            } else {
                logger.debug("Deleted descriptor \(id, privacy: .public)")
            }

            await storeChangeHandler(snapshot)
        } catch {
            logger.error("Failed to insert descriptor: \(error, privacy: .public)")
        }
    }

    private typealias DescriptorStorage = [DeepLinkClientDescriptor.ID: DeepLinkClientDescriptor]

    nonisolated private func readDescriptors() -> DescriptorStorage {
        logger.debug(#function)
        
        guard let data = defaults.data(forKey: storageKey) else {
            logger.debug("No data for \(self.storageKey)")
            return [:]
        }

        do {
            let descriptorsByID = try decoder.decode(DescriptorStorage.self, from: data)

            logger.debug("Fetched \(descriptorsByID.count, privacy: .public) client descriptor(s)")

            return descriptorsByID
        } catch {
            logger.error("Failed to decode management store data: \(error, privacy: .public)")

            return [:]
        }
    }

    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
}

extension UserDefaults: @retroactive @unchecked Sendable { }
