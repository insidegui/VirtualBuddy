import Darwin
import Foundation
import MacDebugProtocol
import Observation
import Virtualization
import VMBridge

struct TunnelControl: VMMessage {
    enum Action: Codable, Sendable {
        case ready
        case snapshot(UInt64, [ServiceTunnel], [ServiceTunnel], [UUID: String])
        case propose(ServiceTunnel)
        case open(UUID, UUID)
        case reverse(UUID, UUID, UInt32)
        case status(UUID, String)
    }
    let session: UUID
    let action: Action
}

enum TunnelReply: VMMessage {
    case ok
    case port(UInt32)
    case failure(String)
}

@Observable @MainActor
public final class TunnelState {
    public fileprivate(set) var available = false
    public fileprivate(set) var rules: [ServiceTunnel] = []
    public fileprivate(set) var requests: [ServiceTunnel] = []
    public fileprivate(set) var status: [UUID: String] = [:]
}

@MainActor
final class TunnelGuestService: GuestService {
    static let capability = "service-tunnels.v1"
    let state = TunnelState()
    var guestSupportsTunnels = false
    var connect: ((UInt32) async throws -> HostLink)?
    var approvedRules: () -> [ServiceTunnel] = { [] }
    private var listeners: [UUID: TunnelListener] = [:]
    /// Listeners that were stopped but whose addresses aren't free yet.
    private var closingListeners = 0
    /// Rules waiting for those addresses, since a rule often replaces one that had the same listener.
    private var rulesAwaitingListeners: [ServiceTunnel] = []
    private var clients: [UUID: (rule: UUID, task: Task<Void, Never>)] = [:]
    private var revision: UInt64 = 0

    override func subscriptions() -> [Subscription] {
        let requests = connection.requests(of: TunnelControl.self, reply: TunnelReply.self)
        return [{
            for await request in requests {
                await self.respond(request)
            }
        }]
    }

    private func respond(_ request: GuestRequest<TunnelControl, TunnelReply>) async {
        guard session == request.payload.session else { return }
        let reply: TunnelReply
        do { reply = try handle(request.payload.action) }
        catch { reply = .failure(error.localizedDescription) }
        try? await request.reply(reply)
    }

    override func activate(notifications: Set<String>) throws {
        if !isHost && context.hostCapabilities.contains(Self.capability) {
            state.available = true
            schedule { _ = try await self.send(.ready) }
        }
    }

    func reloadConfiguration() {
        if isHost && state.available {
            reconcile(approvedRules())
            publish()
        }
    }

    func decline(_ id: UUID) {
        guard state.available, state.requests.contains(where: { $0.id == id }) else { return }
        state.requests.removeAll { $0.id == id }
        publish()
    }

    func propose(_ rule: ServiceTunnel) async throws {
        guard !isHost, state.available else { throw GuestSessionError.disconnected }
        _ = try await send(.propose(rule))
    }

    private func send(_ action: TunnelControl.Action) async throws -> TunnelReply {
        guard let session else { throw GuestSessionError.disconnected }
        let reply = try await connection.request(TunnelControl(session: session, action: action), reply: TunnelReply.self, timeout: requestTimeout)
        try requireSession(session)
        if case .failure(let message) = reply { throw TunnelError(message) }
        return reply
    }

    private func publish() {
        revision += 1
        let snapshot = TunnelControl.Action.snapshot(revision, state.rules, state.requests, state.status.filter { id, _ in
            state.rules.contains { $0.id == id && $0.listensOnHost }
        })
        schedule { _ = try await self.send(snapshot) }
    }

    private func handle(_ action: TunnelControl.Action) throws -> TunnelReply {
        switch action {
        case .ready where isHost && guestSupportsTunnels:
            guard !state.available else { return .ok }
            state.available = true
            reconcile(approvedRules())
            publish()
        case let .snapshot(version, rules, pending, hostStatus) where !isHost && state.available:
            guard version > revision else { return .ok }
            guard rules.count <= 32, pending.count <= 32,
                  rules.indices.allSatisfy({ rules[$0].canAdd(to: Array(rules.prefix($0))) }) else { throw GuestSessionError.invalidReply }
            revision = version
            state.requests = pending
            reconcile(rules)
            for rule in rules where rule.listensOnHost { state.status[rule.id] = hostStatus[rule.id]?.displayableTunnelText }
        case .propose(let rule) where isHost && state.available:
            guard rule.isEnabled, rule.canAdd(to: state.rules), rule.canAdd(to: state.requests) else {
                throw TunnelError("That listener is already mapped or the mapping is invalid.")
            }
            state.requests.append(rule)
            publish()
        case let .open(id, nonce) where !isHost && state.available:
            let rule = try authorized(id, listensOnHost: true)
            return .port(try guestStream(rule, nonce: nonce, client: nil))
        case let .reverse(id, nonce, port) where isHost && state.available:
            let rule = try authorized(id, listensOnHost: false)
            try startClient(rule) {
                try await self.hostStream(rule, nonce: nonce, port: port, client: nil)
            }
        case let .status(id, message) where state.available:
            guard state.rules.contains(where: { $0.id == id && $0.listensOnHost != isHost }) else { throw GuestSessionError.invalidReply }
            state.status[id] = message.displayableTunnelText
        default: throw GuestSessionError.invalidReply
        }
        return .ok
    }

    private func authorized(_ id: UUID, listensOnHost: Bool) throws -> ServiceTunnel {
        guard let rule = state.rules.first(where: { $0.id == id && $0.isEnabled && $0.listensOnHost == listensOnHost }) else {
            throw TunnelError("This tunnel is no longer approved.")
        }
        return rule
    }

    private func reconcile(_ rules: [ServiceTunnel]) {
        for old in state.rules where !rules.contains(old) { stop(old.id) }
        let added = rules.filter { !state.rules.contains($0) && $0.isEnabled && $0.listensOnHost == isHost }
        state.rules = rules
        state.requests.removeAll { request in rules.contains { $0.listener == request.listener && $0.listensOnHost == request.listensOnHost } }
        rulesAwaitingListeners += added
        startAwaitedListeners()
    }

    private func startAwaitedListeners() {
        guard closingListeners == 0 else { return }
        let rules = rulesAwaitingListeners.filter(state.rules.contains)
        rulesAwaitingListeners = []
        for rule in rules {
            do {
                let listener = try TunnelListener(rule.listener)
                try listener.start { [weak self] client in
                    self?.accepted(client, rule: rule)
                } failed: { [weak self] error in
                    self?.report(error.localizedDescription, for: rule)
                }
                listeners[rule.id] = listener
                report("Listening", for: rule)
            } catch { report(error.localizedDescription, for: rule) }
        }
    }

    private func report(_ message: String, for rule: ServiceTunnel) {
        // Failures often quote what the other side replied, which ends up displayed like any other status.
        let message = message.displayableTunnelText
        guard state.rules.contains(rule), state.status[rule.id] != message else { return }
        state.status[rule.id] = message
        if rule.listensOnHost == isHost {
            schedule { _ = try await self.send(.status(rule.id, message)) }
        }
    }

    private func accepted(_ client: DebugSocket, rule: ServiceTunnel) {
        let nonce = UUID()
        do {
            if isHost {
                try startClient(rule) {
                    guard case let .port(port) = try await self.send(.open(rule.id, nonce)) else { throw GuestSessionError.invalidReply }
                    try await self.hostStream(rule, nonce: nonce, port: port, client: client)
                }
            } else {
                _ = try guestStream(rule, nonce: nonce, client: client)
            }
        } catch { report(error.localizedDescription, for: rule) }
    }

    private func startClient(_ rule: ServiceTunnel, action: @escaping @MainActor () async throws -> Void) throws {
        guard clients.count < 32 else { throw TunnelError("The VM has reached its connection limit.") }
        let id = UUID()
        clients[id] = (rule.id, schedule {
            defer { self.clients[id] = nil }
            do { try await action() }
            catch {
                if !Task.isCancelled { self.report(error.localizedDescription, for: rule) }
            }
        })
    }

    struct GuestListener {
        let port: UInt32
        let accept: () async throws -> DebugSocket
    }

    var makeGuestListener: () throws -> GuestListener = {
        let (listener, port) = try DebugSocket.guestListener()
        return GuestListener(port: port, accept: { try await listener.acceptDebuggerFromHost() })
    }

    struct HostLink {
        let stream: DebugSocket
        // Virtualization owns the original descriptor and closes the connection on release.
        let owner: VZVirtioSocketConnection?
    }

    private func guestStream(_ rule: ServiceTunnel, nonce: UUID, client: DebugSocket?) throws -> UInt32 {
        let listener = try makeGuestListener()
        try startClient(rule) {
            if client != nil { _ = try await self.send(.reverse(rule.id, nonce, listener.port)) }
            let link = try await listener.accept()
            try await link.send(nonce)
            try await self.bridge(link, client: client, rule: rule)
        }
        return listener.port
    }

    private func hostStream(_ rule: ServiceTunnel, nonce: UUID, port: UInt32, client: DebugSocket?) async throws {
        guard let connect, port != GuestCommunication.port else { throw GuestSessionError.invalidReply }
        let connection = try await connect(port)
        defer { withExtendedLifetime(connection) {} }
        let link = connection.stream
        guard try await link.receive(UUID.self, within: .seconds(10)) == nonce else { throw GuestSessionError.invalidReply }
        try await bridge(link, client: client, rule: rule)
    }

    private func bridge(_ link: DebugSocket, client: DebugSocket?, rule: ServiceTunnel) async throws {
        try Task.checkCancellation()
        let local: DebugSocket
        if let client {
            let result = try await link.receive(TunnelReply.self, within: .seconds(10))
            if case .failure(let reason) = result { throw TunnelError(reason) }
            guard case .ok = result else { throw GuestSessionError.invalidReply }
            local = client
            report("Listening", for: rule)
        } else {
            do { local = try await rule.destination.connectSocket() }
            catch {
                try await link.send(TunnelReply.failure("Connection to \(rule.destination.address) failed: \(error.localizedDescription)"))
                throw error
            }
            try await link.send(TunnelReply.ok)
        }
        try Task.checkCancellation()
        try await relayTunnel(link, local)
    }

    private func stop(_ id: UUID) {
        if let listener = listeners.removeValue(forKey: id) {
            closingListeners += 1
            listener.stop { [weak self] in
                guard let self else { return }
                closingListeners -= 1
                startAwaitedListeners()
            }
        }
        for (clientID, client) in clients where client.rule == id {
            clients.removeValue(forKey: clientID)
            client.task.cancel()
        }
        state.status[id] = nil
    }

    override func invalidate() {
        super.invalidate()
        for rule in state.rules { stop(rule.id) }
        state.rules = []
        rulesAwaitingListeners = []
        state.requests = []
        state.available = false
        guestSupportsTunnels = false
        revision = 0
    }
}

extension HostGuestSession {
    public var tunnels: TunnelState { engine.tunnels.state }
    public func configureTunnels(device: VZVirtioSocketDevice, approvedRules: @escaping @MainActor () -> [ServiceTunnel]) {
        engine.tunnels.connect = { port in
            // A paused guest may never answer a connect attempt. Let revocation
            // and VM teardown stop waiting even if Virtualization replies later.
            let (connections, continuation) = AsyncThrowingStream<VZVirtioSocketConnection, Error>.makeStream()
            device.connect(toPort: port) { result in
                switch result {
                case .success(let value): continuation.yield(value); continuation.finish()
                case .failure(let error): continuation.finish(throwing: error)
                }
            }
            let timeout = Task {
                try await Task.sleep(for: .seconds(10))
                continuation.finish(throwing: POSIXError(.ETIMEDOUT))
            }
            defer { timeout.cancel() }
            var iterator = connections.makeAsyncIterator()
            guard let connection = try await iterator.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return TunnelGuestService.HostLink(stream: try DebugSocket(owning: dup(connection.fileDescriptor)), owner: connection)
        }
        engine.tunnels.approvedRules = approvedRules
        engine.tunnels.reloadConfiguration()
    }
    public func reloadTunnels() { engine.tunnels.reloadConfiguration() }
    public func declineTunnel(_ id: UUID) { engine.tunnels.decline(id) }
}
