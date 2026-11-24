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

    @Test func extractedSymbolsMustBePlainFilesAndDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let lib = root.appendingPathComponent("usr/lib")
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        try Data(count: 8).write(to: lib.appendingPathComponent("libSystem.B.dylib"))
        #expect(throws: Never.self) { try DebugSymbolCache.requirePlainTree(root) }
        try fm.createSymbolicLink(at: lib.appendingPathComponent("libexample.dylib"), withDestinationURL: URL(fileURLWithPath: "/usr/lib/dyld"))
        #expect(throws: (any Error).self) { try DebugSymbolCache.requirePlainTree(root) }
    }
}
