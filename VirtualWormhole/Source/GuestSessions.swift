import Foundation
import Observation
import OSLog
import VMBridge

@MainActor
public final class HostGuestSession {
    private let engine: GuestSessionEngine
    private var task: Task<Void, Never>?
    public var isConnected: Bool { engine.isConnected }
    public var onDesktopPicture: ((GuestDesktopPicture) -> Void)? {
        get { engine.onDesktopPicture }
        set { engine.onDesktopPicture = newValue }
    }
    public var onNotification: ((String) -> Void)? {
        get { engine.onNotification }
        set { engine.onNotification = newValue }
    }
    public init(connection: VMConnection) {
        engine = GuestSessionEngine(connection: LiveGuestConnection(connection: connection), hostClipboard: .shared, providers: .live)
    }
    @discardableResult public func start() -> Task<Void, Never> {
        let task = engine.start()
        self.task = task
        return task
    }
    public func stop() async { await engine.stop(); task = nil }
    deinit { task?.cancel() }
}

@MainActor @Observable
public final class GuestHostSession {
    private let engine: GuestSessionEngine
    @ObservationIgnored private var task: Task<Void, Never>?
    public var isConnected: Bool { engine.isConnected }
    public init() {
        engine = GuestSessionEngine(connection: LiveGuestConnection(connection: .guest(port: GuestCommunication.port)), providers: .live)
    }
    init(engine: GuestSessionEngine) { self.engine = engine }
    @discardableResult public func start() -> Task<Void, Never> {
        let task = engine.start()
        self.task = task
        return task
    }
    public func stop() async { await engine.stop(); task = nil }
    deinit { task?.cancel() }
    public func sendDesktopPicture() async throws { try await engine.sendDesktopPicture() }
    public func importDomain(with id: String) async throws { try await engine.importDomain(id) }

    public func prepareForTermination() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await self.sendDesktopPicture() }
            group.addTask { try? await Task.sleep(for: .seconds(2)) }
            await group.next()
            group.cancelAll()
            // Cancelling a send cannot interrupt an in-flight frame. Close the
            // connection before joining the final-send task to enforce the deadline.
            await stop()
        }
    }
}

@MainActor @Observable
final class GuestSessionEngine {
    private(set) var isConnected = false
    var onDesktopPicture: ((GuestDesktopPicture) -> Void)?
    var onNotification: ((String) -> Void)?
    private let connection: any GuestConnection
    private let hostClipboard: HostClipboardCoordinator?
    private let providers: GuestFeatureProviders
    private let logger = Logger(subsystem: "codes.rambo.VirtualWormhole", category: "GuestSession")
    private let identity = UUID()
    private var session: UUID?
    private var runTask: Task<Void, Never>?
    private var operations: [UUID: Task<Void, Never>] = [:]
    private var imports: [UUID: Task<Void, Error>] = [:]
    private let requestTimeout: Duration
    private var outboundClipboard: Task<Void, Never>?
    private var inboundClipboard: Task<Void, Never>?
    private var outgoingRevision: UInt64 = 0
    private var incomingRevision: UInt64 = 0
    private var observedClipboardChange = 0
    private var previousClipboard: [ClipboardItem] = []
    private var clipboardInitialized = false
    private var removeNotifications: (() -> Void)?
    private static let notificationNames: Set<String> = ["com.apple.shieldWindowRaised", "com.apple.shieldWindowLowered"]

    private struct PendingDefaults {
        let session: UUID
        let continuation: AsyncThrowingStream<URL, Error>.Continuation
        var file: URL?
        var transfer: Task<Void, Never>?
    }
    private var pendingDefaults: [UUID: PendingDefaults] = [:]

    init(connection: any GuestConnection, hostClipboard: HostClipboardCoordinator? = nil, providers: GuestFeatureProviders, requestTimeout: Duration = .seconds(30)) {
        self.requestTimeout = requestTimeout
        self.connection = connection
        self.hostClipboard = hostClipboard
        self.providers = providers
    }

    @discardableResult func start() -> Task<Void, Never> {
        if let runTask { return runTask }
        // Obtain every subscription synchronously, before the connection can run.
        let states = connection.state
        let initializations = connection.initializationRequests
        let defaults = connection.defaultsRequests
        let clipboard = connection.messages(of: ClipboardUpdate.self)
        let pictures = connection.messages(of: DesktopPictureUpdate.self)
        let notifications = connection.messages(of: GuestNotification.self)
        let offers = connection.fileOffers
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await state in states { await self.stateChanged(state) } }
                group.addTask { for await request in initializations { await self.initialize(request) } }
                group.addTask { for await request in defaults { await self.exportDefaults(request) } }
                group.addTask { for await update in clipboard { await self.receiveClipboard(update) } }
                group.addTask { for await picture in pictures { await self.receivePicture(picture) } }
                group.addTask { for await notification in notifications { await self.receiveNotification(notification) } }
                group.addTask { for await offer in offers { await self.receiveOffer(offer) } }
                group.addTask {
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                        await self.pollClipboard()
                    }
                }
                group.addTask {
                    do { try await self.connection.run() }
                    catch { await self.log(error) }
                }
                // Any unexpectedly finished stream ends this run as well.
                await group.next()
                group.cancelAll()
            }
            invalidateSession()
            let remaining = Array(operations.values)
            let pendingImports = Array(imports.values)
            for task in remaining { await task.value }
            for task in pendingImports { _ = await task.result }
            runTask = nil
        }
        runTask = task
        return task
    }

    func stop() async {
        guard let runTask else { return }
        runTask.cancel()
        await runTask.value
    }

    private func log(_ error: Error) {
        guard !(error is CancellationError) else { return }
        logger.error("Guest communication: \(error.localizedDescription, privacy: .public)")
    }

    @discardableResult
    private func schedule(_ action: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task {
            defer { operations[id] = nil }
            do { try Task.checkCancellation(); try await action() } catch { log(error) }
        }
        operations[id] = task
        return task
    }

    private func invalidateSession() {
        session = nil
        isConnected = false
        clipboardInitialized = false
        hostClipboard?.unregister(identity)
        removeNotifications?()
        removeNotifications = nil
        for task in operations.values { task.cancel() }
        for task in imports.values { task.cancel() }
        outboundClipboard = nil
        inboundClipboard = nil
        outgoingRevision = 0
        incomingRevision = 0
        for pending in pendingDefaults.values { pending.continuation.finish(throwing: GuestSessionError.disconnected) }
    }

    private func requireSession(_ token: UUID) throws {
        try Task.checkCancellation()
        guard session == token else { throw GuestSessionError.disconnected }
    }

    private func stateChanged(_ state: VMConnectionState) {
        guard !Task.isCancelled else { return }
        logger.debug("Transport state: \(String(describing: state), privacy: .public)")
        if state != .connected { invalidateSession(); return }
        guard hostClipboard == nil else { return }
        invalidateSession()
        let token = UUID()
        session = token
        schedule { [self] in
            let reply = try await self.connection.request(InitializeGuest(session: token), reply: InitializeGuestReply.self, timeout: self.requestTimeout)
            try self.requireSession(token)
            self.isConnected = true
            self.logger.notice("Connected to host")
            do {
                self.removeNotifications = try self.providers.notifications(reply.notifications.intersection(Self.notificationNames)) { [weak self] name in
                    guard let self, self.session == token else { return }
                    self.schedule { try self.requireSession(token); try await self.connection.send(GuestNotification(session: token, name: name)) }
                }
            } catch {
                self.log(error)
            }
            try await self.sendDesktopPicture(token: token)
        }
    }

    private func initialize(_ request: InitializationRequest) {
        guard hostClipboard != nil, !Task.isCancelled else { return }
        invalidateSession()
        let token = request.payload.session
        session = token
        schedule { [self] in
            try await request.reply(.init(notifications: Self.notificationNames))
            try self.requireSession(token)
            self.isConnected = true
            self.logger.notice("Initialized guest session")
            self.hostClipboard?.register(self.identity) { [weak self] items in self?.sendClipboard(items) }
        }
    }

    private func pollClipboard() {
        if let hostClipboard {
            hostClipboard.poll()
            return
        }
        guard hostClipboard == nil, isConnected, clipboardInitialized, observedClipboardChange != providers.clipboard.changeCount else { return }
        observedClipboardChange = providers.clipboard.changeCount
        let current = providers.clipboard.read()
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
              hostClipboard == nil || isConnected else { return nil }
        incomingRevision = revision
        inboundClipboard?.cancel()
        return providers.clipboard.changeCount
    }

    private func applyClipboard(_ items: [ClipboardItem], session token: UUID, revision: UInt64, changeCount: Int) {
        guard !Task.isCancelled, session == token, revision == incomingRevision else { return }
        // The initial host snapshot wins even if the guest clipboard changed
        // while downloading it. Subsequent transfers must preserve local edits.
        guard (hostClipboard == nil && !clipboardInitialized) || changeCount == providers.clipboard.changeCount else { return }
        if let hostClipboard {
            hostClipboard.receive(items, from: identity)
        } else {
            if providers.clipboard.read() != items { providers.clipboard.write(items) }
            observedClipboardChange = providers.clipboard.changeCount
            previousClipboard = items
            clipboardInitialized = true
        }
    }

    private func receiveClipboard(_ message: ClipboardUpdate) {
        guard let stamp = beginClipboard(session: message.session, revision: message.revision) else { return }
        applyClipboard(message.items, session: message.session, revision: message.revision, changeCount: stamp)
    }

    private func receiveOffer(_ offer: GuestFileOffer) {
        guard !Task.isCancelled, let metadata = TransferIdentity(offer.metadata), metadata.session == session else {
            schedule { await offer.reject() }; return
        }
        switch metadata.purpose {
        case .clipboard:
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
        case .defaults:
            guard hostClipboard == nil, var pending = pendingDefaults[metadata.operation],
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
    }

    private func exportDefaults(_ request: DefaultsRequest) {
        guard hostClipboard != nil, request.payload.session == session, !Task.isCancelled else { return }
        schedule {
            try await GuestPayloadIO.withTemporaryFile { url in
                let token = request.payload.session
                let response: ExportDefaultsReply
                do {
                    try await self.providers.exportDefaults(request.payload.domain, url)
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
        guard hostClipboard == nil, isConnected, let token = session else { throw GuestSessionError.disconnected }
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
            try await providers.importDefaults(domain, url)
        } catch {
            await cleanupDefaults(operation)
            throw error
        }
        await cleanupDefaults(operation)
    }

    func sendDesktopPicture() async throws {
        guard hostClipboard == nil, let token = session else { throw GuestSessionError.disconnected }
        try await sendDesktopPicture(token: token)
    }

    private func sendDesktopPicture(token: UUID) async throws {
        guard let picture = try await providers.desktopPicture() else {
            logger.debug("No desktop picture is available")
            return
        }
        try requireSession(token)
        logger.debug("Sending desktop picture (\(picture.content.count) bytes)")
        try await connection.send(DesktopPictureUpdate(session: token, type: picture.type, content: picture.content))
    }

    private func receivePicture(_ picture: DesktopPictureUpdate) {
        guard hostClipboard != nil, session == picture.session, !Task.isCancelled else { return }
        logger.debug("Received desktop picture (\(picture.content.count) bytes)")
        onDesktopPicture?(.init(type: picture.type, content: picture.content))
    }

    private func receiveNotification(_ notification: GuestNotification) {
        guard hostClipboard != nil, session == notification.session, Self.notificationNames.contains(notification.name), !Task.isCancelled else { return }
        onNotification?(notification.name)
    }
}
