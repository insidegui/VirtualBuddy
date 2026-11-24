import Foundation
import MacDebugProtocol
import Security
import Testing
@testable import MacDebugHost

final class MemoryBindingStore: DebugBindingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var bindings: [UUID: DebugBinding] = [:]

    func register(_ binding: DebugBinding) { lock.withLock { bindings[binding.id] = binding } }
    func binding(for id: UUID) -> DebugBinding? { lock.withLock { bindings[id] } }
}

struct DebugBindingTests {
    private func request(binding: UUID, product: String, executable: String, developer: String = "file:///Applications/Xcode.app/Contents/Developer") throws -> DebugBuildRequest {
        let json = ["binding": binding.uuidString, "product": product, "executable": executable, "developer": developer,
                    "automaticSigning": false, "options": ["arguments": [String](), "environment": [String: String]()]] as [String: Any]
        return try JSONDecoder().decode(DebugBuildRequest.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func aRunUsesTheApprovedDestinationAndLocalAppPaths() throws {
        let binding = DebugBinding(id: UUID(), destination: UUID(), target: "APP")
        let app = "file:///Build/Products/Debug/Example.app"
        let build = try DebugBuild(request(binding: binding.id, product: app, executable: app + "/Contents/MacOS/Example"), binding: binding)
        #expect(build.destination == binding.destination)
        #expect(build.product.path == "/Build/Products/Debug/Example.app")

        func rejected(_ product: String, _ executable: String, id: UUID = binding.id, developer: String = "file:///Developer") -> Bool {
            (try? DebugBuild(request(binding: id, product: product, executable: executable, developer: developer), binding: binding)) == nil
        }
        #expect(rejected(app, app + "/Contents/MacOS/Example", id: UUID()))
        #expect(rejected("file:///Users/someone/Documents", "file:///Users/someone/Documents/tool"))
        #expect(rejected(app, "file:///Build/Products/Debug/Other.app/Contents/MacOS/Other"))
        #expect(rejected(app, app + "/Contents/MacOS/../../../Other"))
        #expect(rejected("--keepParent", app + "/Contents/MacOS/Example"))
        #expect(rejected("https://example.com/Example.app", "https://example.com/Example.app/Contents/MacOS/Example"))
        #expect(rejected(app, app + "/Contents/MacOS/Example", developer: "Developer"))
    }

    @Test func aForgedKeychainRecordIsNotAnApproval() throws {
        let service = "MacDebugHostTests." + UUID().uuidString
        let store = KeychainDebugBindingStore(service: service)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        defer { while SecItemDelete(query as CFDictionary) == errSecSuccess {} }

        let binding = DebugBinding(id: UUID(), destination: UUID(), target: "APP")
        #expect(try store.binding(for: binding.id) == nil)
        try store.register(binding)
        #expect(try store.binding(for: binding.id) == binding)
        #expect(try store.binding(for: UUID()) == nil)

        // Point the stored record at another destination while keeping its authentication code.
        var item = query
        item[kSecAttrAccount as String] = binding.id.uuidString
        item[kSecReturnData as String] = true
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess)
        let stored = try #require(result as? Data)
        var record = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        var forged = try #require(record["binding"] as? [String: Any])
        forged["destination"] = UUID().uuidString
        record["binding"] = forged
        item[kSecReturnData as String] = nil
        let update = [kSecValueData as String: try JSONSerialization.data(withJSONObject: record)]
        #expect(SecItemUpdate(item as CFDictionary, update as CFDictionary) == errSecSuccess)
        #expect(try store.binding(for: binding.id) == nil)
    }
}
