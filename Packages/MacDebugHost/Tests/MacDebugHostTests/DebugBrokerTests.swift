import Foundation
import MacDebugProtocol
import Testing
@testable import MacDebugHost

@MainActor
private final class UnusedInteraction: DebugProvisioningInteraction {
    func showProgress(destination: UUID, detail: String, cancel: @escaping @MainActor () -> Void) { }
    func resolve(_ request: DebugProvisioningRequest) async throws -> DebugProvisioningAction { .retry }
    func dismiss(destination: UUID) { }
}

@MainActor
struct DebugBrokerTests {
    private let root = URL(fileURLWithPath: "/private/tmp/" + UUID().uuidString.prefix(8))
    private var endpoint: URL { root.appendingPathComponent("host-\(getpid()).sock") }

    private func broker() -> DebugBroker {
        let helper = root.appendingPathComponent("helper")
        return DebugBroker(
            configuration: .init(applicationURL: root, helperURL: helper, runtimeDirectory: root),
            cache: DebugSymbolCache(root: root.appendingPathComponent("Symbols"), helperURL: helper),
            provisioning: .init(cacheDirectory: root.appendingPathComponent("Profiles"), interaction: UnusedInteraction()),
            bindings: MemoryBindingStore(),
            authorize: { },
            resolveDestination: { _ in throw MacDebugError("No destination.") }
        )
    }

    /// The test process is both ends, so it satisfies the broker's requirement for its peer.
    private func refusal() async throws -> String {
        let app = URL(fileURLWithPath: "/Build/Example.app")
        let client = try DebugSocket.unix(endpoint, listening: false)
        try await client.send(DebugBuildRequest(binding: UUID(), product: app, executable: app.appendingPathComponent("Contents/MacOS/Example"),
                                                developer: URL(fileURLWithPath: "/Developer"), automaticSigning: false,
                                                options: .init(arguments: [], environment: [:])))
        guard case .failure(let reason) = try await client.receive(DebugBuildReply.self, within: .seconds(5)) else { return "" }
        return reason
    }

    @Test func theSocketExistsOnlyWhileListening() async throws {
        let broker = broker()
        defer { broker.stop(); try? FileManager.default.removeItem(at: root) }

        try broker.start()
        #expect(try await refusal().contains("has not been approved"))

        broker.stopListening()
        #expect(!FileManager.default.fileExists(atPath: endpoint.path))
        #expect(throws: (any Error).self) { try DebugSocket.unix(endpoint, listening: false) }

        try broker.start()
        #expect(try await refusal().contains("has not been approved"))
    }

    @Test func silentAndExcessClientsDoNotBlockOthers() async throws {
        let broker = broker()
        defer { broker.stop(); try? FileManager.default.removeItem(at: root) }
        broker.requestTimeout = .milliseconds(200)
        broker.clientLimit = 2
        try broker.start()

        let silent = try (0..<4).map { _ in try DebugSocket.unix(endpoint, listening: false) }
        for client in silent {
            // Each is closed by the broker, either at once for being over the limit or at the deadline.
            #expect(try await client.read(upTo: 1).isEmpty)
        }
        #expect(try await refusal().contains("has not been approved"))
    }
}
