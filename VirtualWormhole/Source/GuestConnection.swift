import Foundation
import VMBridge

// The reply closure stays typed at the VMBridge boundary. Only the two app
// request types have responders; there is no second wire protocol here.
struct InitializationRequest: Sendable {
    let payload: InitializeGuest
    let reply: @Sendable (InitializeGuestReply) async throws -> Void
}

struct DefaultsRequest: Sendable {
    let payload: ExportDefaults
    let reply: @Sendable (ExportDefaultsReply) async throws -> Void
}

struct GuestFileOffer: Sendable {
    let metadata: BulkTransferMetadata
    let receive: @Sendable (URL) async throws -> Void
    let reject: @Sendable () async -> Void
}

protocol GuestConnection: Sendable {
    var state: AsyncStream<VMConnectionState> { get }
    var initializationRequests: AsyncStream<InitializationRequest> { get }
    var defaultsRequests: AsyncStream<DefaultsRequest> { get }
    var fileOffers: AsyncStream<GuestFileOffer> { get }
    func messages<M: VMMessage>(of type: M.Type) -> AsyncStream<M>
    func send<M: VMMessage>(_ message: M) async throws
    func request<M: VMMessage, R: VMMessage>(_ message: M, reply: R.Type, timeout: Duration) async throws -> R
    func sendFile(at url: URL, metadata: BulkTransferMetadata) async throws
    func run() async throws
}

struct LiveGuestConnection: GuestConnection {
    let connection: VMConnection
    var state: AsyncStream<VMConnectionState> { connection.state }
    var initializationRequests: AsyncStream<InitializationRequest> {
        connection.requests(of: InitializeGuest.self).mapped { request in
            InitializationRequest(payload: request.payload, reply: { try await request.reply($0) })
        }
    }
    var defaultsRequests: AsyncStream<DefaultsRequest> {
        connection.requests(of: ExportDefaults.self).mapped { request in
            DefaultsRequest(payload: request.payload, reply: { try await request.reply($0) })
        }
    }
    var fileOffers: AsyncStream<GuestFileOffer> {
        connection.bulkTransferOffers.mapped { offer in
            GuestFileOffer(metadata: offer.metadata, receive: { url in
                let transfer = try await offer.accept(to: url)
                do {
                    try await withTaskCancellationHandler {
                        _ = try await transfer.waitForCompletion()
                        try Task.checkCancellation()
                    } onCancel: {
                        Task { await transfer.cancel() }
                    }
                } catch {
                    await transfer.cancel()
                    throw error
                }
            }, reject: { try? await offer.reject() })
        }
    }
    func messages<M: VMMessage>(of type: M.Type) -> AsyncStream<M> {
        connection.messages(of: type).mapped { $0.payload }
    }
    func send<M: VMMessage>(_ message: M) async throws { try await connection.send(message) }
    func request<M: VMMessage, R: VMMessage>(_ message: M, reply: R.Type, timeout: Duration) async throws -> R {
        try await connection.send(message, expecting: reply, timeout: timeout)
    }
    func sendFile(at url: URL, metadata: BulkTransferMetadata) async throws {
        let transfer = try await connection.sendFile(at: url, metadata: metadata)
        do {
            try await withTaskCancellationHandler {
                _ = try await transfer.waitForCompletion()
                try Task.checkCancellation()
            } onCancel: {
                Task { await transfer.cancel() }
            }
        } catch {
            await transfer.cancel()
            throw error
        }
    }
    func run() async throws { try await connection.run() }
}

extension AsyncStream where Element: Sendable {
    func mapped<Value: Sendable>(_ transform: @escaping @Sendable (Element) -> Value) -> AsyncStream<Value> {
        AsyncStream<Value>(unfolding: {
            var iterator = self.makeAsyncIterator()
            guard let element = await iterator.next() else { return nil }
            return transform(element)
        })
    }
}

enum GuestPayloadIO {
    static func withTemporaryFile(_ operation: @MainActor (URL) async throws -> Void) async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await operation(url)
    }

    static func remove(at url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    static func fits<M: VMMessage>(_ message: M) async throws -> Bool {
        try Task.checkCancellation()
        return try JSONEncoder().encode(message).count <= VMConnection.maximumMessageSize
    }
    static func writeClipboard(_ items: [ClipboardItem], to url: URL) async throws {
        try Task.checkCancellation()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(items).write(to: url, options: .atomic)
    }
    static func readClipboard(at url: URL) async throws -> [ClipboardItem] {
        try Task.checkCancellation()
        return try PropertyListDecoder().decode([ClipboardItem].self, from: Data(contentsOf: url))
    }
    static func read(at url: URL) async throws -> Data {
        try Task.checkCancellation()
        return try Data(contentsOf: url)
    }
    static func write(_ data: Data, to url: URL) async throws {
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
    }
    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("VirtualBuddy-\(UUID().uuidString).plist")
    }
}
