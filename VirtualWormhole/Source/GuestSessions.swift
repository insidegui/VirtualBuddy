import Foundation
import Observation
import OSLog
import VMBridge

@MainActor
public final class HostGuestSession {
    private let engine: GuestSessionEngine
    private var task: Task<Void, Never>?
    public var isConnected: Bool { engine.isConnected }
    public var appearance: GuestAppearanceState { engine.appearance.state }
    public var automaticallySyncAppearance: Bool {
        get { engine.appearance.automaticallySync }
        set { engine.appearance.automaticallySync = newValue }
    }
    public func setDarkModeEnabled(_ enabled: Bool) {
        guard !automaticallySyncAppearance else { return }
        engine.appearance.setDarkModeEnabled(enabled)
    }
    public var onDesktopPicture: ((GuestDesktopPicture) -> Void)? {
        get { engine.onDesktopPicture }
        set { engine.onDesktopPicture = newValue }
    }
    public var onSystemInformation: ((GuestSystemInformation) -> Void)? {
        get { engine.onSystemInformation }
        set { engine.onSystemInformation = newValue }
    }
    public var onNotification: ((String) -> Void)? {
        get { engine.onNotification }
        set { engine.onNotification = newValue }
    }
    public init(connection: VMConnection) {
        engine = GuestSessionEngine(connection: LiveGuestConnection(connection: connection), endpoint: .host, hostClipboard: .shared, providers: .live)
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
        engine = GuestSessionEngine(connection: LiveGuestConnection(connection: .guest(port: GuestCommunication.port)), endpoint: .guest, providers: .live)
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
            group.addTask {
                // Both snapshots must finish before the deadline branch closes transport.
                await withTaskGroup(of: Void.self) { snapshots in
                    snapshots.addTask { try? await self.engine.sendSystemInformation() }
                    snapshots.addTask { try? await self.sendDesktopPicture() }
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(2)) }
            await group.next()
            group.cancelAll()
            // Cancelling a send cannot interrupt an in-flight frame. Close the
            // connection before joining the final-send task to enforce the deadline.
            await stop()
        }
    }
}

@MainActor
final class GuestSessionEngine {
    private let context: GuestServiceContext
    private let services: [GuestService]
    private let lifecycle: GuestService
    private let pictures: DesktopPictureGuestService
    private let notifications: NotificationsGuestService
    private let defaults: DefaultsGuestService
    private let systemInformation: SystemInformationGuestService
    let appearance: AppearanceGuestService
    private var runTask: Task<Void, Never>?

    var isConnected: Bool { context.isConnected }
    var onDesktopPicture: ((GuestDesktopPicture) -> Void)? {
        get { pictures.onDesktopPicture }
        set { pictures.onDesktopPicture = newValue }
    }
    var onSystemInformation: ((GuestSystemInformation) -> Void)? {
        get { systemInformation.onSystemInformation }
        set { systemInformation.onSystemInformation = newValue }
    }
    var onNotification: ((String) -> Void)? {
        get { notifications.onNotification }
        set { notifications.onNotification = newValue }
    }

    init(connection: any GuestConnection, endpoint: GuestEndpoint, hostClipboard: HostClipboardCoordinator? = nil, providers: GuestFeatureProviders, requestTimeout: Duration = .seconds(30)) {
        let context = GuestServiceContext(connection: connection, endpoint: endpoint, requestTimeout: requestTimeout)
        self.context = context
        lifecycle = GuestService(context: context)
        pictures = DesktopPictureGuestService(context: context, desktopPicture: providers.desktopPicture)
        notifications = NotificationsGuestService(context: context, observe: providers.notifications)
        defaults = DefaultsGuestService(context: context, exportDomain: providers.exportDefaults, importDomain: providers.importDefaults)
        systemInformation = SystemInformationGuestService(context: context, collect: providers.systemInformation, observe: providers.systemInformationChanges)
        appearance = AppearanceGuestService(context: context, read: providers.appearance, apply: providers.setAppearance, observe: providers.appearanceChanges)
        services = [
            ClipboardGuestService(context: context, clipboard: providers.clipboard, hostClipboard: hostClipboard),
            notifications, pictures, defaults, systemInformation, appearance
        ]
    }

    @discardableResult func start() -> Task<Void, Never> {
        if let runTask { return runTask }
        // Subscribe synchronously so no initialization or service message is lost.
        let states = context.connection.state
        let initializations = context.connection.requests(of: InitializeGuest.self, reply: InitializeGuestReply.self)
        let offers = context.connection.fileOffers
        let subscriptions = services.flatMap { $0.subscriptions() }
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await state in states { await self.stateChanged(state) } }
                group.addTask { for await request in initializations { await self.initialize(request) } }
                group.addTask { for await offer in offers { await self.receiveOffer(offer) } }
                for subscription in subscriptions { group.addTask(operation: subscription) }
                group.addTask {
                    do { try await self.context.connection.run() }
                    catch { await self.lifecycle.log(error) }
                }
                // An unexpectedly finished stream ends the whole connection run.
                await group.next()
                group.cancelAll()
            }
            invalidateSession()
            await lifecycle.drain()
            for service in services { await service.drain() }
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

    private func invalidateSession() {
        context.session = nil
        context.isConnected = false
        context.hostCapabilities = []
        lifecycle.invalidate()
        for service in services { service.invalidate() }
    }

    private func activate(notifications: Set<String>) {
        context.isConnected = true
        for service in services {
            do { try service.activate(notifications: notifications) }
            catch { service.log(error) }
        }
    }

    private func stateChanged(_ state: VMConnectionState) {
        guard !Task.isCancelled else { return }
        if state != .connected { invalidateSession(); return }
        guard context.endpoint == .guest else { return }
        invalidateSession()
        let token = UUID()
        context.session = token
        lifecycle.schedule { [self] in
            let reply = try await context.connection.request(InitializeGuest(session: token), reply: InitializeGuestReply.self, timeout: context.requestTimeout)
            try context.requireSession(token)
            context.hostCapabilities = reply.capabilities ?? []
            activate(notifications: reply.notifications)
        }
    }

    private func initialize(_ request: GuestRequest<InitializeGuest, InitializeGuestReply>) {
        guard context.endpoint == .host, !Task.isCancelled else { return }
        invalidateSession()
        let token = request.payload.session
        context.session = token
        lifecycle.schedule { [self] in
            let names = services.reduce(into: Set<String>()) { $0.formUnion($1.requestedNotifications) }
            try await request.reply(.init(notifications: names, capabilities: [SystemInformationGuestService.capability, AppearanceGuestService.capability]))
            try context.requireSession(token)
            activate(notifications: names)
        }
    }

    private func receiveOffer(_ offer: GuestFileOffer) {
        guard !Task.isCancelled, let metadata = TransferIdentity(offer.metadata),
              metadata.session == context.session,
              let service = services.first(where: { $0.transferPurpose == metadata.purpose }) else {
            lifecycle.schedule { await offer.reject() }
            return
        }
        service.receiveOffer(offer, metadata: metadata)
    }

    func sendSystemInformation() async throws { try await systemInformation.sendSystemInformation() }
    func sendDesktopPicture() async throws { try await pictures.sendDesktopPicture() }
    func importDomain(_ domain: String) async throws { try await defaults.importDomain(domain) }
}
