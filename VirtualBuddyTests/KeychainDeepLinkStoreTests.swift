import Foundation
import Security
import Testing
import DeepLinkSecurity

struct KeychainDeepLinkStoreTests {
    private let service = "codes.rambo.VirtualBuddy.tests.deep-links.\(UUID().uuidString)"
    private let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    private let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")

    private func cleanUp() {
        for suffix in ["clients", "state"] {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrService as String: "\(service).\(suffix)"
            ] as CFDictionary)
        }
    }

    @Test
    func decisionsAndClientsAreKeptTogetherAndOnlyDecisionsChangeAuthorization() async throws {
        defer { cleanUp() }
        let store = KeychainDeepLinkStore(service: service)
        let client = try DeepLinkClient(url: calculator)
        #expect(await store.authorization(for: client) == .undetermined)
        #expect(await !store.hasDescriptor(with: client.id))

        /// A client that only asked is listed, without a decision.
        try await store.insert(DeepLinkClientDescriptor(client: client, authorization: .authorized))
        #expect(await store.hasDescriptor(with: client.id))
        #expect(await store.authorization(for: client) == .undetermined)

        try await store.setAuthorization(.authorized, for: client)
        #expect(await store.authorization(for: client) == .authorized)

        /// Refreshing what's known about the client says nothing about the decision.
        try await store.insert(DeepLinkClientDescriptor(client: client, authorization: .denied))
        #expect(await store.authorization(for: client) == .authorized)
        let listed = try #require(store.currentClientDescriptors.first)
        #expect(listed.id == client.id)
        #expect(listed.authorization == .authorized)
        #expect(listed.url == calculator)
        #expect(listed.isValid)

        /// Another store over the same records sees the same thing, which is what a relaunch amounts to.
        #expect(await KeychainDeepLinkStore(service: service).authorization(for: client) == .authorized)

        try await store.delete(listed)
        #expect(await store.authorization(for: client) == .undetermined)
        #expect(store.currentClientDescriptors.isEmpty)
    }

    @Test
    func everySubscriberFollowsTheList() async throws {
        defer { cleanUp() }
        let store = KeychainDeepLinkStore(service: service)
        let client = try DeepLinkClient(url: calculator)
        var first = store.clientDescriptors().makeAsyncIterator()
        var second = store.clientDescriptors().makeAsyncIterator()
        #expect(await first.next() == [])
        #expect(await second.next() == [])
        try await store.setAuthorization(.denied, for: client)
        #expect(await first.next()?.map(\.authorization) == [.denied])
        #expect(await second.next()?.map(\.authorization) == [.denied])
    }

    @Test
    func migrationOnlyKeepsWhatThePreviousStoresVouchFor() async throws {
        defer { cleanUp() }
        let suite = "codes.rambo.VirtualBuddy.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let legacyAuth = MemoryDeepLinkAuthStore()
        let legacyList = UserDefaultsDeepLinkManagementStore(namespace: "Legacy", suiteName: suite)

        let allowed = try DeepLinkClient(url: calculator)
        let denied = try DeepLinkClient(url: textEdit)
        let undecided = try DeepLinkClient(url: notes)
        try await legacyAuth.setAuthorization(.authorized, for: allowed)
        try await legacyAuth.setAuthorization(.denied, for: denied)
        try await legacyList.insert(DeepLinkClientDescriptor(client: allowed, authorization: .authorized))
        /// What the list in preferences claims about a decision doesn't count, only the decision itself.
        try await legacyList.insert(DeepLinkClientDescriptor(client: denied, authorization: .authorized))
        try await legacyList.insert(DeepLinkClientDescriptor(client: undecided, authorization: .authorized))
        /// An entry pointing an allowed client's identifier at a different app.
        try await legacyAuth.setAuthorization(.authorized, for: undecided)
        try await legacyAuth.setAuthorization(.undetermined, for: undecided)
        try await legacyList.insert(DeepLinkClientDescriptor(clientID: "SPOOFED", clientURL: calculator, authorization: .authorized))

        let legacy = LegacyDeepLinkStores(authStore: legacyAuth, managementStore: legacyList)
        let store = KeychainDeepLinkStore(service: service, legacy: legacy)
        #expect(await store.authorization(for: allowed) == .authorized)
        #expect(await store.authorization(for: denied) == .denied)
        #expect(await store.authorization(for: undecided) == .undetermined)
        #expect(Set(store.currentClientDescriptors.map(\.id)) == [allowed.id, denied.id])
        #expect(legacyList.currentClientDescriptors.isEmpty)

        /// It happens once: what shows up in the previous stores afterwards is never read again.
        try await store.setAuthorization(.denied, for: allowed)
        try await legacyList.insert(DeepLinkClientDescriptor(client: undecided, authorization: .authorized))
        try await legacyAuth.setAuthorization(.authorized, for: undecided)
        let relaunched = KeychainDeepLinkStore(service: service, legacy: legacy)
        #expect(await relaunched.authorization(for: undecided) == .undetermined)
        #expect(await relaunched.authorization(for: allowed) == .denied)
    }
}
