import Foundation
import OSLog
import NIOPosix

final class WHServiceListener: WormholeConnectionProvider {
    private let server: WHGuestServer
    private let logger: Logger
    private var service: WormholeService!

    init<S: WormholeService>(serviceType: S.Type) {
        self.server = WHGuestServer(id: serviceType.id, port: VsockAddress.Port(rawValue: serviceType.port))
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "Listener-\(String(describing: serviceType))")
        self.service = S(provider: self)
    }
    
    func activate() {
        service.activate()
        
        server.activate { [weak self] _ in
            guard let self else { return }
            
            logger.info("Connected")
        } onDisconnect: { [weak self] _ in
            guard let self else { return }
            
            logger.info("Disconnected")
        }
    }

    func broadcast<T>(_ payload: T) async where T : WHPayload {
        await send(payload, to: .host)
    }
    
    func send<T>(_ payload: T, to peerID: WHPeerID) async where T : WHPayload {
        do {
            try await server.send(payload)
        } catch {
            logger.warning("Send failed: \(error, privacy: .public)")
        }
    }
    
    func stream<T>(for payloadType: T.Type) -> AsyncStream<(packet: T, sender: WHPeerID)> where T : WHPayload {
        let typeName = String(describing: payloadType)
        
        return AsyncStream { continuation in
            let cancellable = server.packets
                .filter { $0.payloadType == typeName }
                .sink
            { [weak self] packet in
                guard let self else { return }
                
                do {
                    let payload = try PropertyListDecoder.wormhole.decode(payloadType, from: packet.payload)
                    
                    continuation.yield((payload, .host))
                } catch {
                    self.logger.warning("Payload decoding failed for \(typeName, privacy: .public): \(error, privacy: .public)")
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}

extension WHGuestServer {
    func send<T>(_ payload: T) async throws where T : WHPayload {
        let packet = try WormholePacket(payload)
        try await send(packet)
    }
}
