import Foundation
import OSLog

extension WormholeService {
    /// Creates an instance of the service that's configured as a server on the guest.
    static func guestServer() -> Self {
        Self.init(provider: WHServiceListener(serviceType: Self.self))
    }
}

/// Connection provider used for services on the guest, which only use a single connection: the host.
final class WHServiceListener: WormholeConnectionProvider {
    private let socket: WHSocket
    private let logger: Logger

    init<S: WormholeService>(serviceType: S.Type) {
        self.socket = WHSocket(port: serviceType.port)
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "Listener-\(String(describing: serviceType))")
    }

    private var connection: WHServiceConnection?

    func broadcast<T>(_ payload: T) async where T : WHPayload {
        await send(payload, to: .host)
    }
    
    func send<T>(_ payload: T, to peerID: WHPeerID) async where T : WHPayload {
        do {
            guard let connection else {
                throw WHError("Connection not available.")
            }

            await connection.send(payload)
        } catch {
            logger.warning("Broadcast failed: \(error, privacy: .public)")
        }
    }
    
    func stream<T>(for payloadType: T.Type) -> AsyncThrowingStream<(packet: T, sender: WHPeerID), Error> where T : WHPayload {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                do {
                    for try await event in socket.activate() {
                        switch event {
                        case .activated:
                            self.logger.debug("Socket activated")
                        case .invalidated:
                            self.logger.debug("Socket invalidated")

                            continuation.finish()
                        case .connected(let client):
                            let connection = WHServiceConnection(side: .guest, remotePeerID: .host, connection: client)
                            self.connection = connection

                            Task {
                                do {
                                    for try await payload in connection.stream(for: payloadType) {
                                        continuation.yield((payload, .host))
                                    }

                                    self.logger.debug("Connection stream ended")
                                } catch {
                                    self.logger.warning("Connection stream interrupted: \(error, privacy: .public)")
                                }
                            }
                        case .disconnected:
                            self.logger.debug("Socket disconnected")
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
