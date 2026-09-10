import Foundation
import Testing
import VMBridge
import os
@testable import VirtualWormhole

@Suite @MainActor
struct GuestSessionTests {
    @Test func hostClipboardWinsAndRelaysWithoutEcho() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        #expect(fixture.guestClipboard.items == clipboard("host"))
        fixture.guestClipboard.write(clipboard("guest edit"))
        try await eventually { fixture.hostClipboard.items == clipboard("guest edit") }
        fixture.hostClipboard.write(clipboard("host edit"))
        fixture.coordinator.poll()
        try await eventually { fixture.guestClipboard.items == clipboard("host edit") }
        let count = await fixture.guestConnection.sentClipboardCount
        try await Task.sleep(for: .milliseconds(600))
        #expect(await fixture.guestConnection.sentClipboardCount == count)
        await fixture.stop()
        #expect(!fixture.guest.isConnected)
        #expect(fixture.guestFeatures.notificationRegistrations == fixture.guestFeatures.notificationRemovals)
        #expect(await fixture.guestConnection.running == false)
    }

    @Test func clipboardRelayCanBeDisabledAndVMEventsStaySeparate() async throws {
        let first = await SessionFixture.make()
        let second = await SessionFixture.make(coordinator: first.coordinator)
        try await first.connect()
        try await second.connect()
        first.guestClipboard.write(clipboard("shared"))
        try await eventually { second.guestClipboard.items == clipboard("shared") }
        #expect(first.hostFeatures.pictures.count == 1)
        #expect(second.hostFeatures.pictures.count == 1)
        first.guestFeatures.postNotification?("com.apple.shieldWindowRaised")
        try await eventually { first.hostFeatures.notifications.count == 1 }
        #expect(second.hostFeatures.notifications.isEmpty)
        await first.stop()
        await second.stop()

        let disabled = await SessionFixture.make(relay: false)
        let other = await SessionFixture.make(coordinator: disabled.coordinator)
        try await disabled.connect()
        try await other.connect()
        disabled.guestClipboard.write(clipboard("private"))
        try await eventually { disabled.hostClipboard.items == clipboard("private") }
        #expect(other.guestClipboard.items == clipboard("host"))
        await disabled.stop()
        await other.stop()
    }

    @Test func reconnectRefreshesStateAndRejectsStaleMessages() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        let oldToken = try #require(await fixture.guestConnection.token)
        await fixture.disconnect()
        try await eventually { !fixture.guest.isConnected }
        #expect(fixture.guestFeatures.notificationRemovals == 1)
        fixture.hostClipboard.write(clipboard("while disconnected"))
        await fixture.hostConnection.transition(.connected)
        await fixture.guestConnection.transition(.connected)
        try await eventually { fixture.guest.isConnected && fixture.guestFeatures.notificationRegistrations == 2 }
        #expect(fixture.guestClipboard.items == clipboard("while disconnected"))
        try await fixture.hostConnection.send(ClipboardUpdate(session: oldToken, revision: 999, items: clipboard("stale")))
        try await fixture.guestConnection.send(DesktopPictureUpdate(session: oldToken, type: "public.heic", content: Data([9])))
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.guestClipboard.items == clipboard("while disconnected"))
        #expect(fixture.hostFeatures.pictures.allSatisfy { $0.content == Data([1, 2, 3]) })
        await fixture.stop()
        try await fixture.connect()
        await fixture.stop()
        #expect(fixture.guestFeatures.notificationRegistrations == fixture.guestFeatures.notificationRemovals)
    }

    @Test func oversizedClipboardUsesFilesAndCleansThemUp() async throws {
        let large = [ClipboardItem(type: "public.png", data: Data(repeating: 0xA5, count: 7 * 1024 * 1024))]
        let fixture = await SessionFixture.make(hostItems: large)
        try await fixture.connect()
        #expect(fixture.guestClipboard.items == large)
        #expect(await fixture.hostConnection.sentFiles == 1)
        fixture.guestClipboard.write(large + clipboard("different"))
        try await eventually { fixture.hostClipboard.items == large + clipboard("different") }
        #expect(await fixture.guestConnection.sentFiles == 1)
        await fixture.stop()
        let files = await fixture.hostConnection.files + fixture.guestConnection.files
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func newerClipboardSupersedesSlowTransfer() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        await fixture.hostConnection.delayTransfers(by: .seconds(2))
        fixture.hostClipboard.write([ClipboardItem(type: "public.png", data: Data(repeating: 4, count: 7 * 1024 * 1024))])
        fixture.coordinator.poll()
        try await eventually { await fixture.guestConnection.receivedFiles > 0 }
        fixture.hostClipboard.write(clipboard("newer"))
        fixture.coordinator.poll()
        try await eventually { fixture.guestClipboard.items == clipboard("newer") }
        await fixture.stop()
        let files = await fixture.hostConnection.files + fixture.guestConnection.files
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func initialSnapshotWinsButLaterTransfersPreserveLocalEdits() async throws {
        let large = [ClipboardItem(type: "public.png", data: Data(repeating: 1, count: 7 * 1024 * 1024))]
        let fixture = await SessionFixture.make(hostItems: large)
        await fixture.hostConnection.delayTransfers(by: .milliseconds(200))
        fixture.host.start()
        fixture.guest.start()
        try await eventually { await fixture.guestConnection.receivedFiles == 1 }
        fixture.guestClipboard.write(clipboard("edit during initialization"))
        try await eventually { fixture.guestClipboard.items == large }

        fixture.hostClipboard.write(large + clipboard("another snapshot"))
        fixture.coordinator.poll()
        try await eventually { await fixture.guestConnection.receivedFiles == 2 }
        fixture.guestClipboard.write(clipboard("keep this local edit"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.guestClipboard.items == clipboard("keep this local edit"))
        await fixture.stop()
    }

    @Test func defaultsRequestsAreCorrelatedAndLargeExportsUseFiles() async throws {
        let fixture = await SessionFixture.make()
        fixture.hostFeatures.defaults["small"] = Data("small plist".utf8)
        fixture.hostFeatures.defaults["large"] = Data(repeating: 7, count: 7 * 1024 * 1024)
        try await fixture.connect()
        async let first: Void = fixture.guest.importDomain("small")
        async let second: Void = fixture.guest.importDomain("large")
        try await first
        try await second
        #expect(fixture.guestFeatures.imported == fixture.hostFeatures.defaults)
        #expect(await fixture.hostConnection.sentFiles == 1)
        await #expect(throws: GuestSessionError.self) { try await fixture.guest.importDomain("missing") }
        await fixture.stop()
        let files = await fixture.hostConnection.files + fixture.guestConnection.files
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func defaultsTimeoutCancellationAndDisconnectDoNotImport() async throws {
        let fixture = await SessionFixture.make(timeout: .milliseconds(100))
        fixture.hostFeatures.exportDelay = .seconds(5)
        fixture.hostFeatures.defaults["slow"] = Data([1])
        try await fixture.connect()
        await #expect(throws: VMBridgeError.requestTimedOut) { try await fixture.guest.importDomain("slow") }
        let cancelled = Task { try await fixture.guest.importDomain("slow") }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let disconnected = Task { try await fixture.guest.importDomain("slow") }
        try await Task.sleep(for: .milliseconds(20))
        await fixture.disconnect()
        do { try await disconnected.value; Issue.record("Disconnected import succeeded") } catch { }
        #expect(fixture.guestFeatures.imported.isEmpty)
        await fixture.stop()
    }

    @Test func failedTransferLeavesClipboardUntouched() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        let token = try #require(await fixture.guestConnection.token)
        let identity = TransferIdentity(session: token, operation: UUID(), purpose: .clipboard, revision: 100)
        let paths = RecordedPaths()
        fixture.guestConnection.offerInput.yield(.init(metadata: identity.metadata, receive: { url in
            paths.append(url)
            try Data([1]).write(to: url)
            throw VMBridgeError.bulkTransferIntegrityFailure
        }, reject: {}))
        try await eventually { !paths.values.isEmpty && paths.values.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        #expect(fixture.guestClipboard.items == clipboard("host"))
        await fixture.stop()
    }

    @Test func terminationClosesConnectionBeforeJoiningBlockedSend() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        await fixture.guestConnection.blockPicturesUntilStop()
        let guest = GuestHostSession(engine: fixture.guest)
        let start = ContinuousClock.now
        await guest.prepareForTermination()
        #expect(start.duration(to: .now) < .seconds(3))
        #expect(await fixture.guestConnection.running == false)
        await fixture.host.stop()
    }
}

@MainActor private func eventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw TestFailure.deadline }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private enum TestFailure: Error { case deadline, missingPeer }
private func clipboard(_ text: String) -> [ClipboardItem] { [.init(type: "public.utf8-plain-text", data: Data(text.utf8))] }

@MainActor private final class TestClipboard: GuestClipboard {
    var items: [ClipboardItem]
    var changeCount = 0
    init(_ items: [ClipboardItem]) { self.items = items }
    func read() -> [ClipboardItem] { items }
    func write(_ items: [ClipboardItem]) { self.items = items; changeCount += 1 }
}

@MainActor private final class TestFeatures {
    var notificationRegistrations = 0
    var notificationRemovals = 0
    var postNotification: (@MainActor (String) -> Void)?
    var pictures: [GuestDesktopPicture] = []
    var notifications: [String] = []
    var defaults: [String: Data] = [:]
    var imported: [String: Data] = [:]
    var exportDelay: Duration = .zero

    func providers(clipboard: TestClipboard) -> GuestFeatureProviders {
        .init(clipboard: clipboard, notifications: { [self] _, receive in
            notificationRegistrations += 1
            postNotification = receive
            return { [self] in notificationRemovals += 1; postNotification = nil }
        }, desktopPicture: { GuestDesktopPicture(type: "public.heic", content: Data([1, 2, 3])) }, exportDefaults: { [self] domain, url in
            if exportDelay > .zero { try await Task.sleep(for: exportDelay) }
            guard let data = defaults[domain] else { throw GuestSessionError.unavailableDomain }
            try data.write(to: url)
        }, importDefaults: { [self] domain, url in imported[domain] = try Data(contentsOf: url) })
    }
}

@MainActor private final class SessionFixture {
    let hostConnection: TestConnection
    let guestConnection: TestConnection
    let coordinator: HostClipboardCoordinator
    let hostClipboard: TestClipboard
    let guestClipboard: TestClipboard
    let hostFeatures = TestFeatures()
    let guestFeatures = TestFeatures()
    let host: GuestSessionEngine
    let guest: GuestSessionEngine

    static func make(coordinator: HostClipboardCoordinator? = nil, relay: Bool = true, hostItems: [ClipboardItem] = clipboard("host"), timeout: Duration = .seconds(30)) async -> SessionFixture {
        let host = TestConnection()
        let guest = TestConnection()
        await host.connect(to: guest)
        await guest.connect(to: host)
        return SessionFixture(host: host, guest: guest, coordinator: coordinator, relay: relay, hostItems: hostItems, timeout: timeout)
    }

    private init(host: TestConnection, guest: TestConnection, coordinator: HostClipboardCoordinator?, relay: Bool, hostItems: [ClipboardItem], timeout: Duration) {
        hostConnection = host
        guestConnection = guest
        hostClipboard = coordinator?.clipboard as? TestClipboard ?? TestClipboard(hostItems)
        guestClipboard = TestClipboard(clipboard("old guest"))
        self.coordinator = coordinator ?? HostClipboardCoordinator(clipboard: hostClipboard, relayEnabled: { relay })
        self.host = GuestSessionEngine(connection: host, hostClipboard: self.coordinator, providers: hostFeatures.providers(clipboard: hostClipboard))
        self.guest = GuestSessionEngine(connection: guest, providers: guestFeatures.providers(clipboard: guestClipboard), requestTimeout: timeout)
        self.host.onDesktopPicture = { [hostFeatures] in hostFeatures.pictures.append($0) }
        self.host.onNotification = { [hostFeatures] in hostFeatures.notifications.append($0) }
    }

    func connect() async throws {
        host.start()
        guest.start()
        try await eventually { self.guest.isConnected && self.guestFeatures.postNotification != nil && !self.hostFeatures.pictures.isEmpty && self.guestClipboard.items == self.hostClipboard.items }
    }
    func disconnect() async {
        await hostConnection.transition(.disconnected)
        await guestConnection.transition(.disconnected)
    }
    func stop() async { await guest.stop(); await host.stop() }
}

private final class RecordedPaths: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [URL]())
    var values: [URL] { storage.withLock { $0 } }
    func append(_ url: URL) { storage.withLock { $0.append(url) } }
}

private final class MessageBus: Sendable {
    private let streams = OSAllocatedUnfairLock(initialState: [String: [UUID: AsyncStream<Data>.Continuation]]())
    func subscribe<M: VMMessage>(_ type: M.Type) -> AsyncStream<M> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        streams.withLock { $0[M.messageID, default: [:]][id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.streams.withLock { $0[M.messageID]?[id] = nil } }
        return AsyncStream(unfolding: {
            var iterator = stream.makeAsyncIterator()
            guard let data = await iterator.next() else { return nil }
            return try? JSONDecoder().decode(M.self, from: data)
        })
    }
    func send<M: VMMessage>(_ message: M) throws {
        let data = try JSONEncoder().encode(message)
        let subscribers = streams.withLock { Array(($0[M.messageID] ?? [:]).values) }
        for continuation in subscribers { continuation.yield(data) }
    }
}

private struct TestReply: Sendable {
    let stream: AsyncThrowingStream<Data, Error>
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    init() { (stream, continuation) = AsyncThrowingStream.makeStream() }
    func reply<M: VMMessage>(_ message: M) throws { continuation.yield(try JSONEncoder().encode(message)); continuation.finish() }
    func value() async throws -> Data {
        for try await data in stream { return data }
        throw CancellationError()
    }
}

private actor TestConnection: GuestConnection {
    nonisolated let stateInput = TestEvents<VMConnectionState>()
    nonisolated var state: AsyncStream<VMConnectionState> { stateInput.stream() }
    nonisolated let initializationInput = TestEvents<InitializationRequest>()
    nonisolated var initializationRequests: AsyncStream<InitializationRequest> { initializationInput.stream() }
    nonisolated let defaultsInput = TestEvents<DefaultsRequest>()
    nonisolated var defaultsRequests: AsyncStream<DefaultsRequest> { defaultsInput.stream() }
    nonisolated let offerInput = TestEvents<GuestFileOffer>()
    nonisolated var fileOffers: AsyncStream<GuestFileOffer> { offerInput.stream() }
    nonisolated private let bus = MessageBus()
    private var peer: TestConnection?
    private var transferDelay: Duration = .zero
    private var blockPictures = false
    private var pictureWaiter: CheckedContinuation<Void, Error>?
    private(set) var token: UUID?
    private(set) var sentClipboardCount = 0
    private(set) var sentFiles = 0
    private(set) var receivedFiles = 0
    private(set) var files: [URL] = []
    private(set) var running = false

    func connect(to peer: TestConnection) { self.peer = peer }
    func delayTransfers(by delay: Duration) { transferDelay = delay }
    func blockPicturesUntilStop() { blockPictures = true }
    func transition(_ state: VMConnectionState) { stateInput.yield(state) }
    nonisolated func messages<M: VMMessage>(of type: M.Type) -> AsyncStream<M> { bus.subscribe(type) }
    func send<M: VMMessage>(_ message: M) async throws {
        if message is DesktopPictureUpdate, blockPictures {
            try await withCheckedThrowingContinuation { pictureWaiter = $0 }
        }
        try Task.checkCancellation()
        guard let peer else { throw TestFailure.missingPeer }
        if message is ClipboardUpdate { sentClipboardCount += 1 }
        try peer.bus.send(message)
    }
    func request<M: VMMessage, R: VMMessage>(_ message: M, reply: R.Type, timeout: Duration) async throws -> R {
        try Task.checkCancellation()
        guard let peer else { throw TestFailure.missingPeer }
        let response = TestReply()
        if let message = message as? InitializeGuest {
            token = message.session
            peer.initializationInput.yield(.init(payload: message, reply: { try response.reply($0) }))
        } else if let message = message as? ExportDefaults {
            peer.defaultsInput.yield(.init(payload: message, reply: { try response.reply($0) }))
        }
        let data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await response.value() }
            group.addTask { try await Task.sleep(for: timeout); throw VMBridgeError.requestTimedOut }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
    private func receivedFile(_ url: URL) { receivedFiles += 1; files.append(url) }
    func sendFile(at url: URL, metadata: BulkTransferMetadata) async throws {
        guard let peer else { throw TestFailure.missingPeer }
        sentFiles += 1
        files.append(url)
        let completion = TestReply()
        let delay = transferDelay
        peer.offerInput.yield(.init(metadata: metadata, receive: { destination in
            await peer.receivedFile(destination)
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: url, to: destination)
                completion.continuation.yield(Data())
                completion.continuation.finish()
            } catch {
                completion.continuation.finish(throwing: error)
                throw error
            }
        }, reject: { completion.continuation.finish(throwing: VMBridgeError.bulkTransferRejected) }))
        _ = try await completion.value()
    }
    func run() async throws {
        running = true
        stateInput.yield(.connected)
        do { try await Task.sleep(for: .seconds(3600)) } catch { }
        running = false
        pictureWaiter?.resume(throwing: GuestSessionError.disconnected)
        pictureWaiter = nil
        stateInput.yield(.stopped)
    }
}

private final class TestEvents<Element: Sendable>: Sendable {
    private let subscribers = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<Element>.Continuation]())
    func stream() -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        subscribers.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.subscribers.withLock { $0[id] = nil } }
        return stream
    }
    func yield(_ value: Element) {
        let continuations = subscribers.withLock { Array($0.values) }
        for continuation in continuations { continuation.yield(value) }
    }
}
