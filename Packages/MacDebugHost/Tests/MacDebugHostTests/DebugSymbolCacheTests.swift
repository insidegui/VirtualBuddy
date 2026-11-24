import Foundation
import Testing
@testable import MacDebugHost

struct DebugSymbolCacheTests {
    @Test @MainActor func interruptedDeletionCanBeRetriedFromSettings() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let entry = DebugSymbolCache.Entry(id: "test-build", system: "Test macOS", bytes: 64)
        let directory = root.appendingPathComponent(entry.id)
        let retired = directory.appendingPathComponent(".deleting")
        try fm.createDirectory(at: retired, withIntermediateDirectories: true)
        try Data(count: 64).write(to: retired.appendingPathComponent("library"))
        try JSONEncoder().encode(entry).write(to: directory.appendingPathComponent("complete.json"))

        let cache = DebugSymbolCache(root: root, helperURL: root.appendingPathComponent("helper"))
        let listed = try #require(cache.entries.first)
        try await cache.remove(listed)

        #expect(cache.entries.isEmpty)
        #expect(!fm.fileExists(atPath: directory.path))
    }
}
