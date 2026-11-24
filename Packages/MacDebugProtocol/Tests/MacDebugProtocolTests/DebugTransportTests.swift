import Foundation
import Testing
@testable import MacDebugProtocol

struct DebugTransportTests {
    @Test func framingAndDuplexRelayPreserveArbitraryBytes() async throws {
        func pair() throws -> (DebugSocket, DebugSocket) {
            var fds: [Int32] = [-1, -1]
            #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
            return (try DebugSocket(owning: fds[0]), try DebugSocket(owning: fds[1]))
        }
        let (client, a) = try pair(), (b, server) = try pair()
        let relay = Task { await DebugSocket.relay(a, b) }
        let payload = Data((0..<100000).map { UInt8(truncatingIfNeeded: $0) })
        async let send: Void = client.send(payload)
        #expect(try await server.receive(Data.self) == payload)
        try await send
        let token = UUID()
        try await server.send(token)
        #expect(try await client.receive(UUID.self) == token)
        client.stop()
        await relay.value
        #expect(try await server.read(upTo: 1).isEmpty)
    }

    @Test func cancellingAnUnusedListenerWakesAccept() async throws {
        let file = URL(fileURLWithPath: "/private/tmp/" + UUID().uuidString + ".sock")
        let listener = try DebugSocket.unix(file, listening: true)
        defer { unlink(file.path) }
        let task = Task { try await listener.accept(timeout: 5000) }
        try await Task.sleep(for: .milliseconds(35))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func aLocalPeerIsIdentifiedByItsCodeSignature() async throws {
        let file = URL(fileURLWithPath: "/private/tmp/" + UUID().uuidString + ".sock")
        let listener = try DebugSocket.unix(file, listening: true)
        defer { unlink(file.path) }
        async let accepted = listener.accept(timeout: 5000) { _, _ in }
        let client = try DebugSocket.unix(file, listening: false)
        let server = try await accepted
        // Both ends are this test process, which satisfies only its own requirement.
        let own = try DebugPeerRequirement.currentApplication()
        #expect(throws: Never.self) { try server.requirePeer(own) }
        #expect(throws: Never.self) { try client.requirePeer(own) }
        let other = try DebugPeerRequirement(#"identifier "com.example.another-app" and anchor apple generic"#)
        #expect(throws: (any Error).self) { try server.requirePeer(other) }
        #expect(throws: (any Error).self) { try DebugPeerRequirement("not a requirement") }
    }

    @Test func guestControlledCacheNamesAreConfined() {
        let files = [DebugSystemImages.File(name: "dyld_shared_cache_arm64e", bytes: 200), .init(name: "dyld", bytes: 100)]
        func check(_ build: String, _ extra: [DebugSystemImages.File]) throws {
            try DebugSystemImages(version: "27.0", build: build, architecture: "arm64e", uuid: UUID(), files: files + extra).validate()
        }
        #expect(throws: Never.self) { try check("26A12", [.init(name: "dyld_shared_cache_arm64e.01", bytes: 64)]) }
        #expect(throws: (any Error).self) { try check("../escape", []) }
        #expect(throws: (any Error).self) { try check("26A12", [.init(name: "dyld_shared_cache_arm64e.../escape", bytes: 1)]) }
        #expect(throws: (any Error).self) { try check("26A12", files) }
    }
}
