//
//  WormholePacket.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 08/03/23.
//

import Foundation

struct WormholePacket {
    var magic: UInt32 = Self.magicValue
    var payloadType: String
    var payloadLength: UInt64
    var payload: Data
}

extension WormholePacket {

    static let magicValue: UInt32 = 0x0DF0FECA
    static let magicValueCompressed: UInt32 = 0x01F0FECA
    static let maxUncompressedPayloadSize = 1000000
    static let compressionAlgorithm = NSData.CompressionAlgorithm.lzma

    /// The absolute minimum size an entire packet could be.
    /// Any packet that's not at least this size has something wrong with it.
    static let minimumSize: Int = {
        MemoryLayout<UInt32>.size // magic
        + 2 // payloadType // 1 byte for single character + null terminator
        + MemoryLayout<UInt64>.size // payloadLength
        + 1 // payload // at least 1 byte of payload data
    }()
}

// MARK: - Encoding

extension WormholePacket {

    init<T: Codable>(_ payload: T) throws {
        let data = try JSONEncoder.wormhole.encode(payload)
        let typeName = String(describing: type(of: payload))

        self.init(payloadType: typeName, payloadLength: UInt64(data.count), payload: data)
    }

    func encoded() throws -> Data {
        var encodedMagic = magic
        var encodedPayloadLength = payloadLength
        var encodedPayload = payload

        if payload.count >= Self.maxUncompressedPayloadSize {
            encodedMagic = Self.magicValueCompressed
            let compressedPayload = try (payload as NSData).compressed(using: Self.compressionAlgorithm)
            encodedPayloadLength = UInt64(compressedPayload.count)
            encodedPayload = compressedPayload as Data
        }

        return Data(bytes: &encodedMagic, count: MemoryLayout<UInt32>.size)
        + Data(payloadType.utf8 + [0])
        + Data(bytes: &encodedPayloadLength, count: MemoryLayout<UInt64>.size)
        + encodedPayload
    }

}

// MARK: - Decoding

extension WormholePacket {

    static func decode(from data: Data) throws -> WormholePacket {
        guard data.count >= Self.minimumSize else {
            throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Packet data with length \(data.count) is smaller than the minimum packet length"])
        }

        return try data.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress else {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Couldn't get buffer base address"])
            }

            var byteOffset = 0

            let magic = pointer.load(as: UInt32.self)

            byteOffset += MemoryLayout<UInt32>.size

            let strptr = pointer
                .advanced(by: byteOffset)
                .assumingMemoryBound(to: UInt8.self)

            let payloadType = String(cString: strptr)

            byteOffset += payloadType.count + 1

            var payloadLength = pointer.loadUnaligned(fromByteOffset: byteOffset, as: UInt64.self)

            byteOffset += MemoryLayout<UInt64>.size

            guard UInt64(data.count) > payloadLength else {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Packet payload length \(payloadLength) is out of bounds"])
            }

            let upperBound = Int(byteOffset)+Int(truncatingIfNeeded: payloadLength)

            guard data.count >= upperBound else {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Packet payload length \(payloadLength) is out of bounds"])
            }

            var payload = Data(data[byteOffset..<upperBound])

            guard payload.count == Int(payloadLength) else {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Packet specified payload length \(payloadLength), but payload has length \(payload.count)"])
            }

            if magic == Self.magicValueCompressed {
                payload = try (payload as NSData).decompressed(using: Self.compressionAlgorithm) as Data
                payloadLength = UInt64(payload.count)
            }

            return WormholePacket(
                magic: magic,
                payloadType: payloadType,
                payloadLength: payloadLength,
                payload: payload
            )
        }
    }

}

// MARK: - Streaming

import OSLog

extension WormholePacket {

    static let logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "WormholePacket")

    static func stream(from bytes: FileHandle.AsyncBytes) -> AsyncThrowingStream<WormholePacket, Error> {
        AsyncThrowingStream { continuation in
            Self.logger.debug("Activating stream")

            let task = Task {
                do {
                    var buffer = Data(capacity: WormholePacket.minimumSize)

                    for try await byte in bytes {
                        guard !Task.isCancelled else { break }

//                        Self.logger.debug("RECV: \(buffer.map({ String(format: "%02X", $0) }).joined())")

                        buffer.append(byte)

                        guard buffer.count >= WormholePacket.minimumSize else { continue }

                        if let packet = try? WormholePacket.decode(from: buffer) {
                            continuation.yield(packet)
                            buffer = Data(capacity: WormholePacket.minimumSize)
                        }
                    }

                    Self.logger.debug("Stream ended/cancelled")
                } catch {
                    Self.logger.error("Stream failed: \(error, privacy: .public)")

                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

}

extension JSONDecoder {
    static let wormhole = JSONDecoder()
}

extension JSONEncoder {
    static let wormhole = JSONEncoder()
}
