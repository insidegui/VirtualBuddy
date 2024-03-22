//import Foundation
//import OSLog
//
//final class WHServiceConnection: WormholeConnection {
//    var side: WHConnectionSide
//    var remotePeerID: WHPeerID
//    var connection: WHSocket.Connection
//    private lazy var logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: String(describing: Self.self))
//
//    init(side: WHConnectionSide, remotePeerID: WHPeerID, connection: WHSocket.Connection) {
//        self.side = side
//        self.remotePeerID = remotePeerID
//        self.connection = connection
//    }
//
//    func send<T: WHPayload>(_ payload: T) async {
//        do {
//            let packet = try WormholePacket(payload)
//            let data = try packet.encoded()
//
//            try connection.write(data)
//        } catch {
//            logger.warning("Socket write failed: \(error, privacy: .public)")
//        }
//    }
//
//    func stream<T: WHPayload>(for payloadType: T.Type) -> AsyncThrowingStream<T, Error> {
//        let packetSream = WormholePacket.stream(from: connection.stream)
//
//        return AsyncThrowingStream { continuation in
//            let task = Task.detached { [weak self] in
//                guard let self = self else {
//                    continuation.finish()
//                    return
//                }
//
//                let typeName = String(describing: payloadType)
//
//                do {
//                    let typedStream = packetSream.filter { $0.payloadType == typeName }
//
//                    for try await packet in typedStream {
//                        guard !Task.isCancelled else { return }
//
//                        do {
//                            let decodedPayload = try JSONDecoder.wormhole.decode(payloadType, from: packet.payload)
//
//                            continuation.yield(decodedPayload)
//                        } catch {
//                            self.logger.error("Failed to decode packet of type \(typeName, privacy: .public): \(error, privacy: .public)")
//                        }
//                    }
//
//                    self.logger.notice("Packet stream ended")
//                } catch {
//                    self.logger.error("Packet stream failed: \(error, privacy: .public)")
//
//                    continuation.finish(throwing: error)
//                }
//            }
//
//            continuation.onTermination = { @Sendable _ in
//                task.cancel()
//            }
//        }
//    }
//}
