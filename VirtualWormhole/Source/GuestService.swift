import Foundation
import Observation
import OSLog
import VMBridge

enum GuestEndpoint { case host, guest }

/// Shared connection identity, independent of any particular service.
@MainActor @Observable
final class GuestServiceContext {
    let connection: any GuestConnection
    let endpoint: GuestEndpoint
    let requestTimeout: Duration
    var session: UUID?
    var isConnected = false
    var hostCapabilities: Set<String> = []

    init(connection: any GuestConnection, endpoint: GuestEndpoint, requestTimeout: Duration) {
        self.connection = connection
        self.endpoint = endpoint
        self.requestTimeout = requestTimeout
    }

    func requireSession(_ token: UUID) throws {
        try Task.checkCancellation()
        guard session == token else { throw GuestSessionError.disconnected }
    }
}

/// Services register streams before transport starts and own all their work.
/// Invalidation is synchronous; draining happens after transport has closed so
/// an in-flight send cannot prevent connection teardown.
@MainActor
class GuestService {
    typealias Subscription = @Sendable () async -> Void
    let context: GuestServiceContext
    private var operations: [UUID: Task<Void, Never>] = [:]
    let logger: Logger
    var connection: any GuestConnection { context.connection }
    var session: UUID? { context.session }
    var isConnected: Bool { context.isConnected }
    var requestTimeout: Duration { context.requestTimeout }
    var isHost: Bool { context.endpoint == .host }
    var transferPurpose: TransferIdentity.Purpose? { nil }
    var requestedNotifications: Set<String> { [] }

    init(context: GuestServiceContext) {
        self.context = context
        logger = Logger(subsystem: "codes.rambo.VirtualWormhole", category: String(describing: Self.self))
    }

    func subscriptions() -> [Subscription] { [] }
    func activate(notifications: Set<String>) throws { }
    func receiveOffer(_ offer: GuestFileOffer, metadata: TransferIdentity) {
        schedule { await offer.reject() }
    }
    func invalidate() { for task in operations.values { task.cancel() } }
    func drain() async {
        let remaining = Array(operations.values)
        for task in remaining { await task.value }
    }
    func requireSession(_ token: UUID) throws { try context.requireSession(token) }
    func log(_ error: Error) {
        guard !(error is CancellationError) else { return }
        logger.error("Guest communication: \(error.localizedDescription, privacy: .public)")
    }
    @discardableResult
    func schedule(_ action: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task {
            defer { operations[id] = nil }
            do { try Task.checkCancellation(); try await action() } catch { log(error) }
        }
        operations[id] = task
        return task
    }
}
