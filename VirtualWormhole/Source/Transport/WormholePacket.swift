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
    static let maxUncompressedPayloadSize = 1_000_000
    static let compressionAlgorithm = WHCompressionAlgorithm.lzfse
    static let maxBufferCapacity = 10_000_000

    /// The absolute minimum size an entire packet could be.
    /// Any packet that's not at least this size has something wrong with it.
    static let minimumSize: Int = {
        MemoryLayout<UInt32>.size // magic
        + 2 // payloadType // 1 byte for single character + null terminator
        + MemoryLayout<UInt64>.size // payloadLength
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
            let compressedPayload = try payload.compressed(using: Self.compressionAlgorithm)
            encodedPayloadLength = UInt64(compressedPayload.count)
            encodedPayload = compressedPayload as Data
        }

        return Data(bytes: &encodedMagic, count: MemoryLayout<UInt32>.size)
        + Data(payloadType.utf8 + [0])
        + Data(bytes: &encodedPayloadLength, count: MemoryLayout<UInt64>.size)
        + encodedPayload
    }

}

// MARK: - Streaming

import OSLog

extension WormholePacket {

    static let logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "WormholePacket")

    static func stream<S: AsyncSequence>(from bytes: S) -> AsyncThrowingStream<WormholePacket, Error> where S.Element == UInt8 {
        AsyncThrowingStream { continuation in
            Self.logger.debug("⬇️ Activating stream")

            let task = Task {
                do {
                    var buffer = Data(capacity: WormholePacket.minimumSize)

                    #if DEBUG
                    var start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                    #endif

                    for try await byte in bytes {
                        let readPacket = autoreleasepool {
                            guard !Task.isCancelled else {
                                return false
                            }

                            buffer.append(byte)

//                            print(buffer.map { String(format: "%02X", $0) }.joined())

                            guard buffer.count >= WormholePacket.minimumSize else { return false }

                            if let packet = WormholePacket.decode(from: &buffer) {
                                #if DEBUG
                                if VirtualWormholeConstants.verboseLoggingEnabled {
                                    let duration = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start
                                    start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                                    Self.logger.debug("⏱️ Took \(duration / NSEC_PER_MSEC)ms to stream packet of type \(packet.payloadType) (size: \(ByteCountFormatter.packetSize(packet.payloadLength)))")
                                }
                                #endif

                                continuation.yield(packet)

                                return true
                            } else {
                                return false
                            }
                        }

                        if readPacket {
                            await Task.yield()
                        }
                    }

                    Self.logger.debug("⬇️ Stream ended/cancelled")

                    continuation.finish()
                } catch {
                    Self.logger.error("⬇️ Stream failed: \(error, privacy: .public)")

                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

}

// MARK: - Decoding

extension WormholePacket {

    static func decode(from data: inout Data) -> WormholePacket? {
        guard !data.isEmpty else {
            return nil
        }

        return data.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress else {
                assertionFailure("Couldn't get buffer base address")
                return nil
            }

            var byteOffset = 0

            let magic = pointer.loadUnaligned(as: UInt32.self)

            byteOffset += MemoryLayout<UInt32>.size

            let strptr = pointer
                .advanced(by: byteOffset)
                .assumingMemoryBound(to: UInt8.self)

            let payloadType = String(cString: strptr)

            byteOffset += payloadType.count + 1

            var payloadLength = pointer.loadUnaligned(fromByteOffset: byteOffset, as: UInt64.self)

            byteOffset += MemoryLayout<UInt64>.size

            guard UInt64(data.count) > payloadLength else {
                return nil
            }

            let upperBound = Int(byteOffset)+Int(truncatingIfNeeded: payloadLength)

            guard data.count >= upperBound else {
                return nil
            }

            defer {
                data.removeFirst(upperBound)
            }

            let payloadStart = data.index(data.startIndex, offsetBy: byteOffset)
            let payloadEnd = data.index(data.startIndex, offsetBy: upperBound)
            var payload = Data(data[payloadStart..<payloadEnd])

            guard payload.count == Int(payloadLength) else {
                return nil
            }

            if magic == Self.magicValueCompressed {
                guard let uncompressed = try? payload.decompressed(from: Self.compressionAlgorithm) else { return nil }
                payload = uncompressed
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


extension JSONDecoder {
    static let wormhole = JSONDecoder()
}

extension JSONEncoder {
    static let wormhole = JSONEncoder()
}

#if DEBUG
private extension ByteCountFormatter {
    static let packetLengthFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return f
    }()
    static func packetSize(_ size: UInt64) -> String {
        Self.packetLengthFormatter.string(fromByteCount: Int64(size))
    }
}
#endif
