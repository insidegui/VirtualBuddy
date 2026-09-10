import AppKit
import Virtualization
import OSLog

@MainActor
protocol LegacyClipboardProvider: AnyObject {
    var changeCount: Int { get }
    func read() -> [LegacyClipboardItem]
    func write(_ items: [LegacyClipboardItem])
}

@MainActor
final class LegacySystemClipboard: LegacyClipboardProvider {
    static let types: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .pdf, .png, .tiff]
    private let pasteboard = NSPasteboard.general
    var changeCount: Int { pasteboard.changeCount }

    func read() -> [LegacyClipboardItem] {
        Self.types.compactMap { type in
            if type == .tiff, pasteboard.types?.contains(.png) == true { return nil }
            return pasteboard.data(forType: type).map { .init(type: type.rawValue, value: $0) }
        }
    }

    func write(_ items: [LegacyClipboardItem]) {
        pasteboard.clearContents()
        for item in items { pasteboard.setData(item.value, forType: .init(item.type)) }
    }
}

/// Host-only, clipboard-only compatibility. It has no dependency on VMBridge or
/// VirtualWormhole's sessions, providers, messages, or service registration.
@MainActor
final class LegacyClipboardSession {
    private let toGuest = Pipe()
    private let fromGuest = Pipe()
    private let clipboard: any LegacyClipboardProvider
    private let makeConnection: (FileHandle, FileHandle) throws -> any LegacyClipboardConnection
    private var task: Task<Void, Never>?
    private var lastPing: ContinuousClock.Instant?
    private var previousItems: [LegacyClipboardItem] = []
    private var changeCount = 0
    private var pendingClipboard: [LegacyClipboardItem]?
    private var pendingPong = false
    private var wakeWriter: AsyncStream<Void>.Continuation?
    private let logger = Logger(subsystem: "codes.rambo.VirtualCore", category: "LegacyClipboard")

    init(clipboard: (any LegacyClipboardProvider)? = nil,
         makeConnection: @escaping (FileHandle, FileHandle) throws -> any LegacyClipboardConnection = { try LegacyClipboardPipeConnection(input: $0, output: $1) }) {
        self.clipboard = clipboard ?? LegacySystemClipboard()
        self.makeConnection = makeConnection
    }

    var attachment: VZFileHandleSerialPortAttachment {
        VZFileHandleSerialPortAttachment(fileHandleForReading: toGuest.fileHandleForReading,
                                        fileHandleForWriting: fromGuest.fileHandleForWriting)
    }

    @discardableResult
    func start() throws -> Task<Void, Never> {
        if let task { return task }
        let connection = try makeConnection(fromGuest.fileHandleForReading, toGuest.fileHandleForWriting)
        let (writes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wakeWriter = continuation
        let task = Task {
            await withTaskCancellationHandler {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { for await _ in connection.pings { await self.receivePing() } }
                    group.addTask { for await items in connection.clipboards { await self.receive(items) } }
                    group.addTask {
                        for await _ in writes {
                            while let next = await self.nextWrite() {
                                do {
                                    let data = try Self.encode(next)
                                    try Task.checkCancellation()
                                    try await connection.write(data)
                                } catch {
                                    if !Task.isCancelled { await self.log(error) }
                                    connection.close()
                                    return
                                }
                            }
                        }
                    }
                    group.addTask {
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                            await self.poll()
                        }
                    }
                    await group.next()
                    group.cancelAll()
                    connection.close()
                }
            } onCancel: { connection.close() }
            connection.close()
            await connection.waitUntilClosed()
            continuation.finish()
            wakeWriter = nil
            lastPing = nil
            pendingClipboard = nil
            pendingPong = false
            self.task = nil
        }
        self.task = task
        return task
    }

    func stop() async {
        task?.cancel()
        await task?.value
    }

    private func receivePing() {
        guard !Task.isCancelled else { return }
        if lastPing == nil {
            previousItems = clipboard.read()
            changeCount = clipboard.changeCount
            pendingClipboard = previousItems
        }
        lastPing = .now
        pendingPong = true
        wakeWriter?.yield(())
    }

    private func receive(_ items: [LegacyClipboardItem]) {
        guard !Task.isCancelled, lastPing != nil else { return }
        let supported = items.filter { item in LegacySystemClipboard.types.contains { $0.rawValue == item.type } }
        guard !supported.isEmpty, supported != previousItems else { return }
        previousItems = supported
        pendingClipboard = nil
        clipboard.write(supported)
        changeCount = clipboard.changeCount
    }

    private func poll() {
        guard !Task.isCancelled, let lastPing else { return }
        if lastPing.duration(to: .now) > .seconds(15) {
            self.lastPing = nil
            pendingClipboard = nil
            return
        }
        guard changeCount != clipboard.changeCount else { return }
        changeCount = clipboard.changeCount
        let items = clipboard.read()
        guard items != previousItems else { return }
        previousItems = items
        pendingClipboard = items
        wakeWriter?.yield(())
    }

    private enum Outgoing: Sendable { case pong, clipboard([LegacyClipboardItem]) }

    private func nextWrite() -> Outgoing? {
        guard !Task.isCancelled else { return nil }
        if pendingPong { pendingPong = false; return .pong }
        guard let items = pendingClipboard else { return nil }
        pendingClipboard = nil
        return .clipboard(items)
    }

    private nonisolated static func encode(_ outgoing: Outgoing) throws -> Data {
        switch outgoing {
        case .pong: try LegacyClipboardPacket.encodePong()
        case .clipboard(let items): try LegacyClipboardPacket.encodeClipboard(items)
        }
    }

    private func log(_ error: Error) {
        logger.error("Legacy clipboard connection failed: \(error.localizedDescription, privacy: .public)")
    }
}
