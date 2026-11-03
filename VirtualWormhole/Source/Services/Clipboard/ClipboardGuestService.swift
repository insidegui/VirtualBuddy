import Foundation
import VMBridge

@MainActor
final class ClipboardGuestService: GuestService {
    private let clipboard: any GuestClipboard
    private let hostClipboard: HostClipboardCoordinator?
    private let identity = UUID()
    private var outboundClipboard: Task<Void, Never>?
    private var inboundClipboard: Task<Void, Never>?
    private var outgoingRevision: UInt64 = 0
    private var incomingRevision: UInt64 = 0
    private var observedClipboardChange = 0
    private var previousClipboard: [ClipboardItem] = []
    private var clipboardInitialized = false
    override var transferPurpose: TransferIdentity.Purpose? { .clipboard }

    init(context: GuestServiceContext, clipboard: any GuestClipboard, hostClipboard: HostClipboardCoordinator?) {
        self.clipboard = clipboard
        self.hostClipboard = hostClipboard
        super.init(context: context)
    }

    override func subscriptions() -> [Subscription] {
        let updates = connection.messages(of: ClipboardUpdate.self)
        return [
            { for await update in updates { await self.receiveClipboard(update) } },
            {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                    await self.pollClipboard()
                }
            }
        ]
    }

    override func activate(notifications: Set<String>) {
        hostClipboard?.register(identity) { [weak self] items in self?.sendClipboard(items) }
    }

    override func invalidate() {
        super.invalidate()
        clipboardInitialized = false
        hostClipboard?.unregister(identity)
        outboundClipboard = nil
        inboundClipboard = nil
        outgoingRevision = 0
        incomingRevision = 0
    }

    private func pollClipboard() {
        if let hostClipboard {
            hostClipboard.poll()
            return
        }
        guard !isHost, isConnected, clipboardInitialized, observedClipboardChange != clipboard.changeCount else { return }
        observedClipboardChange = clipboard.changeCount
        let current = clipboard.read()
        guard current != previousClipboard else { return }
        previousClipboard = current
        inboundClipboard?.cancel()
        sendClipboard(current)
    }

    private func sendClipboard(_ items: [ClipboardItem]) {
        guard let token = session else { return }
        outgoingRevision += 1
        let revision = outgoingRevision
        outboundClipboard?.cancel()
        outboundClipboard = schedule {
            let message = ClipboardUpdate(session: token, revision: revision, items: items)
            let inline = try await GuestPayloadIO.fits(message)
            try self.requireSession(token)
            if inline {
                try await self.connection.send(message)
            } else {
                try await GuestPayloadIO.withTemporaryFile { url in
                    try await GuestPayloadIO.writeClipboard(items, to: url)
                    try self.requireSession(token)
                    let metadata = TransferIdentity(session: token, operation: UUID(), purpose: .clipboard, revision: revision).metadata
                    try await self.connection.sendFile(at: url, metadata: metadata)
                }
            }
        }
    }

    private func beginClipboard(session token: UUID, revision: UInt64) -> Int? {
        guard session == token, revision > incomingRevision,
              !isHost || isConnected else { return nil }
        incomingRevision = revision
        inboundClipboard?.cancel()
        return clipboard.changeCount
    }

    private func applyClipboard(_ items: [ClipboardItem], session token: UUID, revision: UInt64, changeCount: Int) {
        guard !Task.isCancelled, session == token, revision == incomingRevision else { return }
        // The initial host snapshot wins even if the guest clipboard changed
        // while downloading it. Subsequent transfers must preserve local edits.
        guard (!isHost && !clipboardInitialized) || changeCount == clipboard.changeCount else { return }
        if let hostClipboard {
            hostClipboard.receive(items, from: identity)
        } else {
            if clipboard.read() != items { clipboard.write(items) }
            observedClipboardChange = clipboard.changeCount
            previousClipboard = items
            clipboardInitialized = true
        }
    }

    private func receiveClipboard(_ message: ClipboardUpdate) {
        guard let stamp = beginClipboard(session: message.session, revision: message.revision) else { return }
        applyClipboard(message.items, session: message.session, revision: message.revision, changeCount: stamp)
    }

    override func receiveOffer(_ offer: GuestFileOffer, metadata: TransferIdentity) {
        guard let stamp = beginClipboard(session: metadata.session, revision: metadata.revision) else {
            schedule { await offer.reject() }; return
        }
        inboundClipboard = schedule {
            try await GuestPayloadIO.withTemporaryFile { url in
                try await offer.receive(url)
                try self.requireSession(metadata.session)
                let items = try await GuestPayloadIO.readClipboard(at: url)
                self.applyClipboard(items, session: metadata.session, revision: metadata.revision, changeCount: stamp)
            }
        }
    }
}
