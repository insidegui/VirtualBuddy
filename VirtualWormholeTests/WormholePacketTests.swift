//
//  VirtualWormholeTests.swift
//  VirtualWormholeTests
//
//  Created by Guilherme Rambo on 08/03/23.
//

import XCTest
@testable import VirtualWormhole
import CryptoKit

final class WormholePacketTests: XCTestCase {

    func testPacketDecodingWithTestPayload() throws {
        let payload = TestPayload()
        let packet = try WormholePacket(payload)
        var data = try packet.encoded()

        guard let decodedPacket = WormholePacket.decode(from: &data) else {
            XCTAssert(false, "Expected to decode a packet")
            return
        }

        XCTAssertEqual(decodedPacket.magic, packet.magic)
        XCTAssertEqual(decodedPacket.payloadType, packet.payloadType)
        XCTAssertEqual(decodedPacket.payloadLength, packet.payloadLength)
        XCTAssertEqual(decodedPacket.payload.count, packet.payload.count)
        XCTAssertEqual(decodedPacket.payload, packet.payload)
    }

    func testPacketDecodingRespectsLength() throws {
        let payload = TestPayload()

        var packet = try WormholePacket(payload)
        packet.payloadLength = 1

        var data = try packet.encoded()

        guard let decodedPacket = WormholePacket.decode(from: &data) else {
            XCTAssert(false, "Expected to decode a packet")
            return
        }

        XCTAssertEqual(Int(packet.payloadLength), decodedPacket.payload.count)
    }

    func testCompressedPacketEncodeDecode() async throws {
        let payload = TestPayload(data: .random(count: WormholePacket.maxUncompressedPayloadSize + 1))

        let packet = try WormholePacket(payload)

        var data = try packet.encoded()

        guard let decodedPacket = WormholePacket.decode(from: &data) else {
            XCTAssert(false, "Expected to decode a packet")
            return
        }

        XCTAssertTrue(data.isEmpty, "Expected buffer with full packet to be empty after decoding")
        XCTAssertEqual(decodedPacket.magic, WormholePacket.magicValueCompressed)
        XCTAssertEqual(decodedPacket.payload, packet.payload)
    }

    func testCompressedPacketEncodeDecodeLargePayload() async throws {
        let payload = TestPayload(data: .random(count: 10_000_000))

        let packet = try WormholePacket(payload)

        var data = try packet.encoded()

        guard let decodedPacket = WormholePacket.decode(from: &data) else {
            XCTAssert(false, "Expected to decode a packet")
            return
        }

        XCTAssertEqual(decodedPacket.magic, WormholePacket.magicValueCompressed)
        XCTAssertEqual(decodedPacket.payload, packet.payload)
    }

    func testPacketStreaming() async throws {
        let (handle, _) = FileHandle.testStreamSmallPayloads()

        let expect = expectation(description: "Receive 6 packets")
        expect.expectedFulfillmentCount = 6

        let streamTask = Task {
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

            var packets = [WormholePacket]()

            for try await packet in WormholePacket.stream(from: handle.bytes) {
                packets.append(packet)

                expect.fulfill()
            }

            let end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

            let duration = (end - start) / NSEC_PER_MSEC

            print("⏱️ STREAM DURATION: \(duration)ms")

            return packets
        }

        await fulfillment(of: [expect], timeout: 3)
        streamTask.cancel()

        let packets = try await streamTask.value

        XCTAssertEqual(packets.count, 6)

        for (index, packet) in packets.enumerated() {
            XCTAssertEqual(packet.magic, 0x0DF0FECA)
            XCTAssertEqual(packet.payloadType, "TestPayload")
            XCTAssertEqual(packet.payloadType, "TestPayload")
            let payload = try JSONDecoder.wormhole.decode(TestPayload.self, from: packet.payload)
            XCTAssertEqual(payload.data, Data.testPayloads[index])
        }
    }

}

struct TestPayload: Codable {
    var message = "Hello, World!"
    var number = 42
    var data = Data([0xAA,0xBB,0xCC,0xDD,0xEE,0xFF])
}

extension Data {
    var hexDump: String {
        map { String(format: "%02X", $0) }.joined()
    }

    static func empty(count: Int) -> Data {
        let bytes = [UInt8](repeating: 0, count: count)
        return Data(bytes)
    }

    static func random(count: Int) -> Data {
        var bytes = [Int8](repeating: 0, count: count)

        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        assert(status == errSecSuccess, "Failed to generate random data for testing")

        return Data(bytes: bytes, count: count)
    }
}

extension FileHandle {
    static var testStream: FileHandle {
        guard let url = Bundle(for: WormholePacketTests.self).url(forResource: "TestStream", withExtension: "bin") else {
            fatalError("Missing TestStream.bin in WormholeTests bundle!")
        }
        return try! FileHandle(forReadingFrom: url)
    }
}

extension Data {
    static let testPayloads: [Data] = [
        Data.empty(count: 500_000),
        Data.empty(count: 16_000),
        Data.empty(count: 102_010),
        Data.empty(count: 11_006),
        Data.empty(count: 13_231),
        Data.empty(count: 1_200),
    ]

    static let testMedium = Data.random(count: 1_000_000)
    static let testLarge = Data.random(count: 3_000_000)
}

extension FileHandle {

    static func testStreamSmallPayloads() -> (readHandle: FileHandle, task: Task<Void, Never>) {
        let pipe = Pipe()
        let writeHandle = pipe.fileHandleForWriting
        let readHandle = pipe.fileHandleForReading

        let writeTask = Task {
            for i in (0..<6) {
                guard !Task.isCancelled else { return }

                let payload = TestPayload(data: .testPayloads[i])
                try! writeHandle.write(contentsOf: WormholePacket(payload).encoded())
            }
        }

        return (readHandle, writeTask)
    }
}
