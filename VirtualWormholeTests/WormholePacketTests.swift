//
//  VirtualWormholeTests.swift
//  VirtualWormholeTests
//
//  Created by Guilherme Rambo on 08/03/23.
//

import XCTest
@testable import VirtualWormhole

final class WormholePacketTests: XCTestCase {

    func testPacketEncodingWithTestPayload() throws {
        let payload = TestPayload()
        let packet = try WormholePacket(payload)
        let data = packet.encoded()

        XCTAssertEqual(data.hexDump, "CAFEF00D546573745061796C6F6164003A000000000000007B226D657373616765223A2248656C6C6F2C20576F726C6421222C226E756D626572223A34322C2264617461223A227172764D3365375C2F227D")
    }

    func testPacketDecodingWithTestPayload() throws {
        let payload = TestPayload()
        let packet = try WormholePacket(payload)
        let data = packet.encoded()

        let decodedPacket = try WormholePacket.decode(from: data)

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

        let data = packet.encoded()

        let decodedPacket = try WormholePacket.decode(from: data)
        XCTAssertEqual(Int(packet.payloadLength), decodedPacket.payload.count)
    }

    func testPacketStreaming() async throws {
        let handle = FileHandle.testStream

        var packets = [WormholePacket]()

        for try await packet in WormholePacket.stream(from: handle.bytes) {
            packets.append(packet)

            guard packets.count < 6 else { break }
        }

        XCTAssertEqual(packets.count, 6)

        for packet in packets {
            XCTAssertEqual(packet.magic, 0x0DF0FECA)
            XCTAssertEqual(packet.payloadType, "TestPayload")
            XCTAssertEqual(packet.payloadLength, 58)
            XCTAssertEqual(packet.payload.count, 58)
            XCTAssertEqual(packet.payload, Data("{\"message\":\"Hello, World!\",\"number\":42,\"data\":\"qrvM3e7\\/\"}".utf8))
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
}

extension FileHandle {
    static var testStream: FileHandle {
        guard let url = Bundle(for: WormholePacketTests.self).url(forResource: "TestStream", withExtension: "bin") else {
            fatalError("Missing TestStream.bin in WormholeTests bundle!")
        }
        return try! FileHandle(forReadingFrom: url)
    }
}
