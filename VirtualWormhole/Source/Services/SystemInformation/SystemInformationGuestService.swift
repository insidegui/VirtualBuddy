import Foundation
import VMBridge

struct SystemInformationUpdate: VMMessage {
    let session: UUID
    let revision: UInt64
    let information: GuestSystemInformation
}

@MainActor
final class SystemInformationGuestService: GuestService {
    static let capability = "systemInformation.v1"
    private let collect: () async throws -> GuestSystemInformation
    private let observe: (@escaping @MainActor () -> Void) -> () -> Void
    private let refreshInterval: Duration
    private var removeObservers: (() -> Void)?
    private var updateTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var receivedRevision: UInt64 = 0
    var onSystemInformation: ((GuestSystemInformation) -> Void)?

    init(context: GuestServiceContext, collect: @escaping () async throws -> GuestSystemInformation,
         observe: @escaping (@escaping @MainActor () -> Void) -> () -> Void,
         refreshInterval: Duration = .seconds(300)) {
        self.collect = collect
        self.observe = observe
        self.refreshInterval = refreshInterval
        super.init(context: context)
    }

    override func subscriptions() -> [Subscription] {
        let updates = connection.messages(of: SystemInformationUpdate.self)
        return [{ for await update in updates { await self.receive(update) } }]
    }

    override func activate(notifications: Set<String>) {
        guard !isHost, context.hostCapabilities.contains(Self.capability), let token = session else { return }
        removeObservers = observe { [weak self] in self?.requestRefresh() }
        requestRefresh()
        schedule {
            while !Task.isCancelled {
                try await Task.sleep(for: self.refreshInterval)
                try self.requireSession(token)
                self.requestRefresh()
            }
        }
    }

    private func requestRefresh() {
        guard updateTask == nil, let token = session else { return }
        updateTask = schedule {
            defer { if self.session == token { self.updateTask = nil } }
            try await self.sendSystemInformation()
        }
    }

    func sendSystemInformation() async throws {
        guard !isHost, context.hostCapabilities.contains(Self.capability), let token = session else { return }
        revision += 1
        let currentRevision = revision
        let information = try await collect()
        try requireSession(token)
        try await connection.send(SystemInformationUpdate(session: token, revision: currentRevision, information: information))
    }

    private func receive(_ update: SystemInformationUpdate) {
        guard isHost, session == update.session, !Task.isCancelled,
              update.revision > receivedRevision else { return }
        receivedRevision = update.revision
        onSystemInformation?(update.information)
    }

    override func invalidate() {
        super.invalidate()
        removeObservers?()
        removeObservers = nil
        updateTask = nil
        revision = 0
        receivedRevision = 0
    }
}
