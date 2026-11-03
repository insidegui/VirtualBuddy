import Foundation
import Observation
import VMBridge

struct GuestAppearanceUpdate: VMMessage {
    let session: UUID
    let revision: UInt64
    let isDarkModeEnabled: Bool
}

struct SetGuestAppearance: VMMessage {
    let session: UUID
    let isDarkModeEnabled: Bool
}

enum SetGuestAppearanceReply: VMMessage {
    case applied(GuestAppearanceUpdate)
    case failure(String)
}

@MainActor @Observable
public final class GuestAppearanceState {
    /// `nil` until a compatible guest reports its system appearance.
    public internal(set) var isDarkModeEnabled: Bool?
    public internal(set) var isUpdating = false
    public internal(set) var errorMessage: String?

    init() { }
}

@MainActor
final class AppearanceGuestService: GuestService {
    static let capability = "appearance.v1"
    let state = GuestAppearanceState()
    private let read: () -> Bool?
    private let apply: (Bool) throws -> Void
    private let observe: (@escaping @MainActor () -> Void) -> () -> Void
    private var removeObserver: (() -> Void)?
    private var revision: UInt64 = 0
    private var receivedRevision: UInt64 = 0
    private var pendingAppearance: Bool?
    private var commandTask: Task<Void, Never>?

    var automaticallySync = false {
        didSet {
            guard automaticallySync != oldValue, isHost else { return }
            if automaticallySync {
                syncHostAppearance()
            } else {
                // An already-sent command may finish, but queued sync work is dropped.
                pendingAppearance = nil
            }
        }
    }

    init(context: GuestServiceContext, read: @escaping () -> Bool?, apply: @escaping (Bool) throws -> Void,
         observe: @escaping (@escaping @MainActor () -> Void) -> () -> Void) {
        self.read = read
        self.apply = apply
        self.observe = observe
        super.init(context: context)
    }

    override func subscriptions() -> [Subscription] {
        let updates = connection.messages(of: GuestAppearanceUpdate.self)
        let requests = connection.requests(of: SetGuestAppearance.self, reply: SetGuestAppearanceReply.self)
        return [
            { for await update in updates { await self.receive(update) } },
            { for await request in requests { await self.receive(request) } }
        ]
    }

    override func activate(notifications: Set<String>) {
        guard isHost || context.hostCapabilities.contains(Self.capability) else { return }
        removeObserver = observe { [weak self] in
            guard let self else { return }
            if self.isHost { self.syncHostAppearance() } else { self.sendAppearance() }
        }
        if isHost { syncHostAppearance() } else { sendAppearance() }
    }

    private func snapshot() -> GuestAppearanceUpdate? {
        guard let token = session, let enabled = read() else { return nil }
        revision += 1
        return .init(session: token, revision: revision, isDarkModeEnabled: enabled)
    }

    private func sendAppearance() {
        guard isConnected, let update = snapshot() else { return }
        schedule {
            try self.requireSession(update.session)
            try await self.connection.send(update)
        }
    }

    private func receive(_ update: GuestAppearanceUpdate) {
        guard isHost, session == update.session, !Task.isCancelled,
              update.revision > receivedRevision else { return }
        let firstReport = state.isDarkModeEnabled == nil
        receivedRevision = update.revision
        state.isDarkModeEnabled = update.isDarkModeEnabled
        // The first report confirms that this guest supports appearance commands.
        if firstReport { syncHostAppearance() }
    }

    private func receive(_ request: GuestRequest<SetGuestAppearance, SetGuestAppearanceReply>) {
        guard !isHost, isConnected, context.hostCapabilities.contains(Self.capability),
              request.payload.session == session, !Task.isCancelled else { return }
        schedule {
            try self.requireSession(request.payload.session)
            let reply: SetGuestAppearanceReply
            do {
                if self.read() != request.payload.isDarkModeEnabled {
                    try self.apply(request.payload.isDarkModeEnabled)
                }
                guard let update = self.snapshot() else {
                    throw GuestSessionError.remote("The guest’s system appearance is unavailable.")
                }
                reply = .applied(update)
            } catch {
                reply = .failure(error.localizedDescription)
            }
            try await request.reply(reply)
        }
    }

    func setDarkModeEnabled(_ enabled: Bool) {
        guard isHost, isConnected, state.isDarkModeEnabled != nil, let token = session else { return }
        pendingAppearance = enabled
        state.errorMessage = nil
        guard commandTask == nil else { return }
        state.isUpdating = true
        // One request at a time: rapid host changes coalesce to the latest value,
        // and an older acknowledgement cannot overwrite a newer guest report.
        commandTask = schedule {
            defer {
                if self.session == token {
                    self.commandTask = nil
                    self.state.isUpdating = false
                }
            }
            do {
                while let enabled = self.pendingAppearance {
                    self.pendingAppearance = nil
                    try self.requireSession(token)
                    let reply = try await self.connection.request(
                        SetGuestAppearance(session: token, isDarkModeEnabled: enabled),
                        reply: SetGuestAppearanceReply.self, timeout: self.requestTimeout
                    )
                    try self.requireSession(token)
                    switch reply {
                    case .applied(let update):
                        guard update.session == token else { throw GuestSessionError.invalidReply }
                        self.receive(update)
                    case .failure(let message):
                        throw GuestSessionError.remote(message)
                    }
                }
            } catch {
                if self.session == token, !(error is CancellationError) {
                    self.state.errorMessage = error.localizedDescription
                }
                throw error
            }
        }
    }

    private func syncHostAppearance() {
        guard isHost, automaticallySync, let enabled = read() else { return }
        setDarkModeEnabled(enabled)
    }

    override func invalidate() {
        super.invalidate()
        removeObserver?()
        removeObserver = nil
        commandTask = nil
        pendingAppearance = nil
        revision = 0
        receivedRevision = 0
        state.isDarkModeEnabled = nil
        state.isUpdating = false
        state.errorMessage = nil
    }
}
