import Foundation
import OSLog
import NIOPosix
import Virtualization

/// Implements the client-side of a service, running in VirtualBuddy on the host.
final class WHServiceClient: WormholeConnectionProvider {
    private let client: WHGuestClient
    private let logger: Logger
    private var service: WormholeService!

    init<S: WormholeService>(serviceType: S.Type, device: VZVirtioSocketDevice) {
        self.client = WHGuestClient(device: device, port: serviceType.port)
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "Client-\(String(describing: serviceType))")
        self.service = S(provider: self)
    }

    init<S: WormholeService>(serviceType: S.Type, fileDescriptor: Int32, invalidationHandler: (() -> Void)?) {
        self.client = WHGuestClient(fileDescriptor: fileDescriptor, invalidationHandler: invalidationHandler)
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "Client-\(String(describing: serviceType))")
        self.service = S(provider: self)
    }

    func activate() {
        service.activate()

        client.activate()
    }

    func send<T>(_ payload: T) async where T : WHPayload {
        do {
            try await client.send(payload)
        } catch {
            logger.warning("Send failed: \(error, privacy: .public)")
        }
    }

    func stream<T: WHPayload>(for payloadType: T.Type) -> AsyncStream<T> {
        let typeName = String(describing: payloadType)

        return AsyncStream { continuation in
            let cancellable = client.packets
                .filter { $0.payloadType == typeName }
                .sink
            { [weak self] packet in
                guard let self else { return }

                do {
                    let payload = try PropertyListDecoder.wormhole.decode(payloadType, from: packet.payload)

                    continuation.yield(payload)
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

extension WHGuestClient {
    func send<T>(_ payload: T) async throws where T : WHPayload {
        let packet = try WormholePacket(payload)
        try await send(packet)
    }
}
