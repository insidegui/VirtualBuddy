import Foundation
import VMBridge

@MainActor
final class DefaultsGuestService: GuestService {
    private let exportDomain: (String, URL) async throws -> Void
    private let importDomainFile: (String, URL) async throws -> Void
    private var imports: [UUID: Task<Void, Error>] = [:]
    private struct PendingDefaults {
        let session: UUID
        let continuation: AsyncThrowingStream<URL, Error>.Continuation
        var file: URL?
        var transfer: Task<Void, Never>?
    }
    private var pendingDefaults: [UUID: PendingDefaults] = [:]
    override var transferPurpose: TransferIdentity.Purpose? { .defaults }

    init(context: GuestServiceContext, exportDomain: @escaping (String, URL) async throws -> Void, importDomain: @escaping (String, URL) async throws -> Void) {
        self.exportDomain = exportDomain
        self.importDomainFile = importDomain
        super.init(context: context)
    }

    override func subscriptions() -> [Subscription] {
        let requests = connection.requests(of: ExportDefaults.self, reply: ExportDefaultsReply.self)
        return [{ for await request in requests { await self.exportDefaults(request) } }]
    }

    override func invalidate() {
        super.invalidate()
        for task in imports.values { task.cancel() }
        for pending in pendingDefaults.values { pending.continuation.finish(throwing: GuestSessionError.disconnected) }
    }

    override func drain() async {
        let pending = Array(imports.values)
        await super.drain()
        for task in pending { _ = await task.result }
    }

    override func receiveOffer(_ offer: GuestFileOffer, metadata: TransferIdentity) {
        guard !isHost, var pending = pendingDefaults[metadata.operation],
              pending.session == metadata.session, pending.file == nil else {
            schedule { await offer.reject() }; return
        }
        let url = GuestPayloadIO.temporaryURL()
        pending.file = url
        pendingDefaults[metadata.operation] = pending
        let task = schedule {
            do {
                try await offer.receive(url)
                try self.requireSession(metadata.session)
                guard let pending = self.pendingDefaults[metadata.operation] else { throw CancellationError() }
                pending.continuation.yield(url)
                pending.continuation.finish()
            } catch {
                await GuestPayloadIO.remove(at: url)
                self.pendingDefaults[metadata.operation]?.continuation.finish(throwing: error)
                throw error
            }
        }
        pendingDefaults[metadata.operation]?.transfer = task
    }

    private func exportDefaults(_ request: GuestRequest<ExportDefaults, ExportDefaultsReply>) {
        guard isHost, request.payload.session == session, !Task.isCancelled else { return }
        schedule {
            try await GuestPayloadIO.withTemporaryFile { url in
                let token = request.payload.session
                let response: ExportDefaultsReply
                do {
                    try await self.exportDomain(request.payload.domain, url)
                    try self.requireSession(token)
                    let data = try await GuestPayloadIO.read(at: url)
                    let inline = ExportDefaultsReply.inline(data)
                    response = try await GuestPayloadIO.fits(inline) ? inline : .file
                } catch {
                    try self.requireSession(token)
                    try await request.reply(.failure(error.localizedDescription))
                    return
                }
                try self.requireSession(token)
                try await request.reply(response)
                if case .file = response {
                    try self.requireSession(token)
                    try await self.connection.sendFile(at: url, metadata: TransferIdentity(session: token, operation: request.payload.operation, purpose: .defaults).metadata)
                }
            }
        }
    }

    func importDomain(_ domain: String) async throws {
        let id = UUID()
        let task = Task { try await self.performImport(domain) }
        imports[id] = task
        defer { imports[id] = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func cleanupDefaults(_ operation: UUID) async {
        guard let pending = pendingDefaults.removeValue(forKey: operation) else { return }
        pending.continuation.finish()
        pending.transfer?.cancel()
        await pending.transfer?.value
        if let file = pending.file { await GuestPayloadIO.remove(at: file) }
    }

    private func performImport(_ domain: String) async throws {
        try await GuestPayloadIO.withTemporaryFile { url in
            try await self.performImport(domain, inlineURL: url)
        }
    }

    private func performImport(_ domain: String, inlineURL: URL) async throws {
        try Task.checkCancellation()
        guard !isHost, isConnected, let token = session else { throw GuestSessionError.disconnected }
        let operation = UUID()
        let (files, continuation) = AsyncThrowingStream<URL, Error>.makeStream()
        pendingDefaults[operation] = PendingDefaults(session: token, continuation: continuation)
        do {
            let reply = try await connection.request(ExportDefaults(session: token, operation: operation, domain: domain), reply: ExportDefaultsReply.self, timeout: self.requestTimeout)
            try requireSession(token)
            let url: URL
            switch reply {
            case .failure(let error): throw GuestSessionError.remote(error)
            case .inline(let data):
                try await GuestPayloadIO.write(data, to: inlineURL)
                url = inlineURL
            case .file:
                url = try await withThrowingTaskGroup(of: URL.self) { group in
                    group.addTask {
                        for try await file in files { return file }
                        throw GuestSessionError.disconnected
                    }
                    let timeout = requestTimeout
                    group.addTask { try await Task.sleep(for: timeout); throw VMBridgeError.requestTimedOut }
                    defer { group.cancelAll() }
                    guard let file = try await group.next() else { throw GuestSessionError.invalidReply }
                    return file
                }
            }
            try requireSession(token)
            try await importDomainFile(domain, url)
        } catch {
            await cleanupDefaults(operation)
            throw error
        }
        await cleanupDefaults(operation)
    }

}
