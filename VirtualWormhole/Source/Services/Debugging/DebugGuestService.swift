import Foundation
import VMBridge
import MacDebugProtocol
import MacDebugTarget

struct DebugRequest: VMMessage {
    enum Action: Codable, Sendable {
        case prepare
        case image(String, UUID)
        case launch(DebugLaunchOptions)
        case cancel
    }
    let session: UUID
    let run: UUID
    let action: Action
}

enum DebugReply: VMMessage {
    case images(DebugSystemImages)
    case listening(DebugEndpoint)
    case done
    case failure(String)
}

public struct DebugEndpoint: Codable, Sendable {
    public let port: UInt32
    public let bundlePath: String
}

@MainActor
final class DebugGuestService: GuestService {
    static let capability = "debug-launch-v1"
    var available = false
    override var transferPurpose: TransferIdentity.Purpose? { .debugging }

    private struct Incoming {
        let destination: URL
        var expectedBytes: Int64? = nil
        var task: Task<Void, Error>?
    }
    private var incoming: [UUID: Incoming] = [:]
    private var run: TargetDebugRun?
    private var server: Task<Void, Never>?
    private var preparing: Task<Void, Never>?
    private var exports: [UUID: Task<Void, Never>] = [:]

    override func subscriptions() -> [Subscription] {
        guard !isHost else { return [] }
        let requests = connection.requests(of: DebugRequest.self, reply: DebugReply.self)
        return [{ for await request in requests { await self.respond(request) } }]
    }

    func cancelRun() {
        server?.cancel()
        server = nil
        run?.cancel()
        preparing?.cancel()
        preparing = nil
        for task in exports.values { task.cancel() }
        exports.removeAll()
        let transfers = incoming.values.compactMap(\.task)
        for transfer in transfers { transfer.cancel() }
        incoming.removeAll()
        if let run {
            Task {
                for transfer in transfers { _ = await transfer.result }
                withExtendedLifetime(run) {}
            }
        }
        run = nil
    }

    override func invalidate() {
        super.invalidate()
        cancelRun()
        available = false
    }

    override func receiveOffer(_ offer: GuestFileOffer, metadata: TransferIdentity) {
        guard let entry = incoming[metadata.operation], entry.task == nil,
              entry.expectedBytes == nil || entry.expectedBytes == offer.byteCount else {
            schedule { await offer.reject() }
            return
        }
        incoming[metadata.operation]?.task = Task { try await offer.receive(entry.destination) }
    }

    private func respond(_ request: GuestRequest<DebugRequest, DebugReply>) {
        let message = request.payload
        guard message.session == session else { return }
        let task = schedule {
            defer {
                if case .image(_, let transfer) = message.action { self.exports[transfer] = nil }
            }
            do {
                let reply = try await self.perform(message)
                try self.requireSession(message.session)
                try await request.reply(reply)
            } catch {
                try? await request.reply(.failure(error.localizedDescription))
            }
        }
        if case .launch = message.action { preparing = task }
        if case .image(_, let transfer) = message.action { exports[transfer] = task }
    }

    private func perform(_ request: DebugRequest) async throws -> DebugReply {
        try requireSession(request.session)
        if case .prepare = request.action {
            guard run == nil else { throw MacDebugError("A debugger session is already active in this VM.") }
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/VirtualBuddy/Debugging")
            let run = try TargetDebugRun(id: request.run, storageRoot: root)
            self.run = run
            incoming[run.id] = Incoming(destination: run.archiveURL)
            return .images(run.images)
        }
        guard let run, run.id == request.run else { throw MacDebugError("This debug session expired.") }
        switch request.action {
        case .prepare: throw GuestSessionError.invalidReply
        case .cancel:
            cancelRun()
            return .done
        case .image(let name, let transfer):
            let image = try run.imageURL(named: name)
            try await connection.sendFile(at: image, metadata: TransferIdentity(session: request.session, operation: transfer, purpose: .debugging).metadata)
            return .done
        case .launch(let options):
            guard let upload = incoming[request.run], let task = upload.task, server == nil else { throw GuestSessionError.invalidReply }
            try await task.value
            try requireSession(request.session)
            let app = try await run.install()
            try requireSession(request.session)
            guard self.run === run else { throw CancellationError() }
            let (listener, port) = try DebugSocket.guestListener()
            server = schedule { [self] in
                defer { if self.run === run { cancelRun() } }
                let host = try await listener.acceptDebuggerFromHost()
                try await host.send(run.id)
                try await run.serve(over: host, options: options)
            }
            return .listening(.init(port: port, bundlePath: app.path))
        }
    }

    func request(_ action: DebugRequest.Action, run: UUID) async throws -> DebugReply {
        guard available, let token = session else { throw MacDebugError("Update VirtualBuddyGuest in the VM and log in to its desktop.") }
        let reply = try await connection.request(DebugRequest(session: token, run: run, action: action), reply: DebugReply.self, timeout: .seconds(1200))
        try requireSession(token)
        if case .failure(let reason) = reply { throw MacDebugError(reason) }
        return reply
    }

    func fetch(_ file: DebugSystemImages.File, run: UUID, to destination: URL) async throws {
        let id = UUID()
        incoming[id] = Incoming(destination: destination, expectedBytes: file.bytes)
        defer { incoming.removeValue(forKey: id)?.task?.cancel() }
        guard case .done = try await request(.image(file.name, id), run: run), let task = incoming[id]?.task else { throw GuestSessionError.invalidReply }
        try await task.value
    }
}

extension HostGuestSession {
    public var supportsDebugging: Bool { engine.debugging.available }
    public func prepareDebugRun(_ id: UUID) async throws -> DebugSystemImages {
        guard case .images(let images) = try await engine.debugging.request(.prepare, run: id) else { throw GuestSessionError.invalidReply }
        try images.validate()
        return images
    }
    public func transferDebugImage(_ file: DebugSystemImages.File, run: UUID, to destination: URL) async throws {
        try await engine.debugging.fetch(file, run: run, to: destination)
    }
    public func launchDebugApp(_ archive: URL, options: DebugLaunchOptions, run: UUID) async throws -> DebugEndpoint {
        let service = engine.debugging
        guard let token = service.session else { throw GuestSessionError.disconnected }
        try await service.connection.sendFile(at: archive, metadata: TransferIdentity(session: token, operation: run, purpose: .debugging).metadata)
        try service.requireSession(token)
        guard case .listening(let endpoint) = try await service.request(.launch(options), run: run) else { throw GuestSessionError.invalidReply }
        return endpoint
    }
    public func cancelDebugRun(_ id: UUID) async {
        _ = try? await engine.debugging.request(.cancel, run: id)
    }
}
