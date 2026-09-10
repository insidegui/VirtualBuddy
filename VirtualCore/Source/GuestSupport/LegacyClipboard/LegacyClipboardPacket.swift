import Foundation
import Compression

/// The two message types understood by the host-only legacy clipboard adapter.
/// Names and JSON keys intentionally match the archived VirtualBuddyGuest apps.
enum LegacyClipboardEvent: Sendable {
    case ping
    case clipboard([LegacyClipboardItem])
}

struct LegacyClipboardItem: Codable, Equatable, Sendable {
    var type: String
    var value: Data
}

struct LegacyClipboardMessage: Codable {
    var timestamp: Date
    var data: [LegacyClipboardItem]
}

struct LegacyClipboardPacket {
    static let maximumPayloadSize = 64 * 1024 * 1024
    private static let magic: UInt32 = 0x0DF0FECA
    private static let compressedMagic: UInt32 = 0x01F0FECA
    private var buffer = Data()

    enum InvalidPacket: Error { case header, size }

    /// Called only by the serial input queue. Unknown services are discarded
    /// without decoding or decompressing their payloads.
    mutating func append(_ bytes: Data) throws -> [LegacyClipboardEvent] {
        buffer.append(bytes)
        var events: [LegacyClipboardEvent] = []
        while buffer.count >= 4 {
            let magic = buffer.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
            guard magic == Self.magic || magic == Self.compressedMagic else { throw InvalidPacket.header }
            guard let terminator = buffer.dropFirst(4).prefix(129).firstIndex(of: 0) else {
                guard buffer.count < 133 else { throw InvalidPacket.header }
                break
            }
            let typeLength = buffer.distance(from: buffer.startIndex, to: terminator) - 4
            guard typeLength > 0,
                  let type = String(data: buffer.dropFirst(4).prefix(typeLength), encoding: .utf8) else { throw InvalidPacket.header }
            let lengthOffset = 4 + typeLength + 1
            let headerSize = lengthOffset + 8
            guard buffer.count >= headerSize else { break }
            let length = buffer.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: lengthOffset, as: UInt64.self)) }
            guard length <= Self.maximumPayloadSize else { throw InvalidPacket.size }
            let packetSize = headerSize + Int(length)
            guard buffer.count >= packetSize else { break }
            if type == "WHPing" {
                events.append(.ping)
            } else if type == "ClipboardMessage" {
                var payload = Data(buffer.dropFirst(headerSize).prefix(Int(length)))
                if magic == Self.compressedMagic { payload = try Self.decompress(payload) }
                let message = try JSONDecoder().decode(LegacyClipboardMessage.self, from: payload)
                events.append(.clipboard(message.data))
            }
            buffer = Data(buffer.dropFirst(packetSize))
        }
        return events
    }

    static func encodeClipboard(_ items: [LegacyClipboardItem]) throws -> Data {
        try encode(type: "ClipboardMessage", payload: JSONEncoder().encode(LegacyClipboardMessage(timestamp: .now, data: items)))
    }

    static func encodePong() throws -> Data {
        try encode(type: "WHPong", payload: JSONEncoder().encode(["date": Date.now]))
    }

    static func encode(type: String, payload: Data) throws -> Data {
        guard payload.count <= maximumPayloadSize else { throw InvalidPacket.size }
        let compressed = payload.count >= 1_000_000
        let body = compressed ? try (payload as NSData).compressed(using: .lzma) as Data : payload
        guard body.count <= maximumPayloadSize else { throw InvalidPacket.size }
        var magic = (compressed ? compressedMagic : self.magic).littleEndian
        var length = UInt64(body.count).littleEndian
        return Data(bytes: &magic, count: 4) + Data(type.utf8) + Data([0])
            + Data(bytes: &length, count: 8) + body
    }

    private static func decompress(_ data: Data) throws -> Data {
        var result = Data()
        let filter = try OutputFilter(.decompress, using: .lzma) { chunk in
            guard let chunk else { return }
            guard chunk.count <= maximumPayloadSize - result.count else { throw InvalidPacket.size }
            result.append(chunk)
        }
        try filter.write(data)
        try filter.finalize()
        return result
    }
}
