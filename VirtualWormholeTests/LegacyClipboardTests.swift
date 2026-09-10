import Foundation
import Testing
import os
@testable import VirtualCore

@Suite(.timeLimit(.minutes(1))) @MainActor
struct LegacyClipboardTests {
    @Test func eligibilityRequiresAnUnsupportedGuestOS() {
        let legacy = CatalogLegacyGuestAppVersion(id: "old", url: URL(fileURLWithPath: "/old.dmg"), sha384: "",
            guestAppVersion: "2.1", minGuestVersion: "13", maxGuestVersion: "13.99.99")
        #expect(LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: "13.6", minimumVersion: "14", selectedLegacyApp: nil))
        #expect(!LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: "14", minimumVersion: "14", selectedLegacyApp: legacy))
        #expect(!LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: "27", minimumVersion: "14", selectedLegacyApp: legacy))
        #expect(!LegacyClipboardEligibility.isRequired(guestType: .linux, guestVersion: "12", minimumVersion: "14", selectedLegacyApp: legacy))
        #expect(!LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: nil, minimumVersion: "14", selectedLegacyApp: nil))
        #expect(LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: nil, minimumVersion: "14", selectedLegacyApp: legacy))
        #expect(!LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: nil, minimumVersion: "13", selectedLegacyApp: legacy))
        #expect(!LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: "12", minimumVersion: .empty, selectedLegacyApp: legacy))
        var exclusiveRange = legacy
        exclusiveRange.maxGuestVersion = "14"
        #expect(LegacyClipboardEligibility.isRequired(guestType: .mac, guestVersion: nil, minimumVersion: "14", selectedLegacyApp: exclusiveRange))
    }

    @Test func archivedWireFormatSurvivesFragmentationAndUnrelatedServices() throws {
        // Fixed little-endian frame and JSON layout used by releases 1.4 and 2.1.
        let fixture = legacyFixture
        let ignored = historicalFrame("DesktopPictureMessage", payload: Data([1, 2, 3]), compressed: true)
        let ping = historicalFrame("WHPing", payload: Data(#"{"date":0}"#.utf8))
        let stream = ignored + fixture + ping + fixture
        var parser = LegacyClipboardPacket()
        var items: [[LegacyClipboardItem]] = []
        var pings = 0
        for offset in stride(from: 0, to: stream.count, by: 7) {
            for event in try parser.append(Data(stream.dropFirst(offset).prefix(7))) {
                switch event {
                case .ping: pings += 1
                case .clipboard(let data): items.append(data)
                }
            }
        }
        #expect(pings == 1)
        #expect(items == [legacyItems("legacy"), legacyItems("legacy")])
    }

    @Test func compressedClipboardInteroperatesWithHistoricalNSDataEncoding() throws {
        let items = [LegacyClipboardItem(type: "public.png", value: Data(repeating: 0xAB, count: 1_000_001))]
        let encoded = try LegacyClipboardPacket.encodeClipboard(items)
        #expect(Array(encoded.prefix(4)) == [0xCA, 0xFE, 0xF0, 0x01])
        let body = try (Data(encoded.dropFirst(29)) as NSData).decompressed(using: .lzma) as Data
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["timestamp"] is Double)
        let decoded = try JSONDecoder().decode(LegacyClipboardMessage.self, from: body)
        #expect(decoded.data == items)

        let historicalBody = try JSONEncoder().encode(LegacyClipboardMessage(timestamp: .now, data: items))
        let historicalCompressed = try (historicalBody as NSData).compressed(using: .lzma) as Data
        var parser = LegacyClipboardPacket()
        let events = try parser.append(historicalFrame("ClipboardMessage", payload: historicalCompressed, compressed: true))
        guard case .clipboard(let received) = try #require(events.first) else { Issue.record("Missing clipboard"); return }
        #expect(received == items)
    }

    @Test func malformedFramesAreBounded() throws {
        var parser = LegacyClipboardPacket()
        #expect(throws: (any Error).self) { try parser.append(Data([0, 0, 0, 0])) }
        parser = LegacyClipboardPacket()
        let badLength = Data([0xCA, 0xFE, 0xF0, 0x0D]) + Data("ClipboardMessage".utf8) + Data([0]) + Data(repeating: 0xFF, count: 8)
        #expect(throws: (any Error).self) { try parser.append(badLength) }
        parser = LegacyClipboardPacket()
        #expect(throws: (any Error).self) { try parser.append(Data([0xCA, 0xFE, 0xF0, 0x0D]) + Data(repeating: 65, count: 129)) }
        parser = LegacyClipboardPacket()
        #expect(throws: (any Error).self) { try parser.append(historicalFrame("ClipboardMessage", payload: Data([1, 2, 3]), compressed: true)) }
    }

    @Test func pipeReadsLegacyPacketsAndWritesPongs() async throws {
        let input = Pipe()
        let output = Pipe()
        let connection = try LegacyClipboardPipeConnection(input: input.fileHandleForReading, output: output.fileHandleForWriting)
        var clips = connection.clipboards.makeAsyncIterator()
        try input.fileHandleForWriting.write(contentsOf: legacyFixture.prefix(13))
        try input.fileHandleForWriting.write(contentsOf: legacyFixture.dropFirst(13))
        #expect(await clips.next() == legacyItems("legacy"))
        let pong = try LegacyClipboardPacket.encodePong()
        try await connection.write(pong)
        #expect(try output.fileHandleForReading.read(upToCount: pong.count) == pong)
        #expect(String(data: pong.dropFirst(4).prefix(6), encoding: .utf8) == "WHPong")
        connection.close()
        await connection.waitUntilClosed()
        #expect(await clips.next() == nil)
    }

    @Test func stopInterruptsBlockedPipeWrite() async throws {
        let input = Pipe()
        let output = Pipe()
        let connection = try LegacyClipboardPipeConnection(input: input.fileHandleForReading, output: output.fileHandleForWriting)
        let write = Task { try await connection.write(Data(repeating: 1, count: 2 * 1024 * 1024)) }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        connection.close()
        await connection.waitUntilClosed()
        await #expect(throws: (any Error).self) { try await write.value }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func clipboardSyncSuppressesEchoesAndRestartsCleanly() async throws {
        let clipboard = TestLegacyClipboard()
        let first = TestLegacyConnection()
        let second = TestLegacyConnection()
        var connections = [first, second]
        let session = LegacyClipboardSession(clipboard: clipboard, makeConnection: { _, _ in connections.removeFirst() })
        try session.start()
        first.pingOutput.yield(())
        try await legacyEventually { first.writes.count == 2 }
        #expect(first.clipboardWrites == [legacyItems("host")])
        first.clipboardOutput.yield(legacyItems("guest"))
        try await legacyEventually { clipboard.items == legacyItems("guest") }
        try await Task.sleep(for: .milliseconds(600))
        #expect(first.writes.count == 2)
        clipboard.write(legacyItems("new host"))
        try await legacyEventually { first.clipboardWrites.last == legacyItems("new host") }
        await session.stop()
        #expect(first.isClosed)
        first.clipboardOutput.yield(legacyItems("stale"))
        try session.start()
        second.pingOutput.yield(())
        try await legacyEventually { second.clipboardWrites == [legacyItems("new host")] }
        await session.stop()
        #expect(second.isClosed)
    }
}

private let legacyFixture = Data(base64Encoded: "yv7wDUNsaXBib2FyZE1lc3NhZ2UATQAAAAAAAAB7InRpbWVzdGFtcCI6MCwiZGF0YSI6W3sidHlwZSI6InB1YmxpYy51dGY4LXBsYWluLXRleHQiLCJ2YWx1ZSI6ImJHVm5ZV041In1dfQ==")!

private func legacyItems(_ text: String) -> [LegacyClipboardItem] {
    [.init(type: "public.utf8-plain-text", value: Data(text.utf8))]
}

private func historicalFrame(_ type: String, payload: Data, compressed: Bool = false) -> Data {
    var length = UInt64(payload.count).littleEndian
    return Data([0xCA, 0xFE, 0xF0, compressed ? 0x01 : 0x0D]) + Data(type.utf8) + Data([0])
        + Data(bytes: &length, count: 8) + payload
}

@MainActor private func legacyEventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private final class TestLegacyClipboard: LegacyClipboardProvider {
    var items = legacyItems("host")
    var changeCount = 0
    func read() -> [LegacyClipboardItem] { items }
    func write(_ items: [LegacyClipboardItem]) { self.items = items; changeCount += 1 }
}

private final class TestLegacyConnection: LegacyClipboardConnection, @unchecked Sendable {
    let pings: AsyncStream<Void>
    let pingOutput: AsyncStream<Void>.Continuation
    let clipboards: AsyncStream<[LegacyClipboardItem]>
    let clipboardOutput: AsyncStream<[LegacyClipboardItem]>.Continuation
    // Test observations are protected by one lock; streams are thread-safe.
    private let state = OSAllocatedUnfairLock(initialState: (writes: [Data](), closed: false))
    var writes: [Data] { state.withLock { $0.writes } }
    var isClosed: Bool { state.withLock { $0.closed } }
    var clipboardWrites: [[LegacyClipboardItem]] {
        writes.compactMap { data in
            var parser = LegacyClipboardPacket()
            guard let event = try? parser.append(data).first, case .clipboard(let items) = event else { return nil }
            return items
        }
    }
    init() {
        (pings, pingOutput) = AsyncStream<Void>.makeStream()
        (clipboards, clipboardOutput) = AsyncStream<[LegacyClipboardItem]>.makeStream()
    }
    func write(_ data: Data) async throws { state.withLock { $0.writes.append(data) } }
    func close() { state.withLock { $0.closed = true }; pingOutput.finish(); clipboardOutput.finish() }
    func waitUntilClosed() async { }
}
