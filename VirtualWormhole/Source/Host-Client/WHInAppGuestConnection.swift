import Foundation
import OSLog
import Combine
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

/// Runs a socket client for the guest server in the VirtualBuddy app process.
final class WHInAppGuestConnection: WHGuestConnection {
    private let logger = Logger(for: WHInAppGuestConnection.self)

    private let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

    private var channel: (any Channel)?

    private var invalidationHandler: ((WHInAppGuestConnection) -> Void)?

    var packets: AnyPublisher<WormholePacket, Never> { inboundPacketSubject.eraseToAnyPublisher() }
    private let inboundPacketSubject = PassthroughSubject<WormholePacket, Never>()

    private let outboundPacketSubject = PassthroughSubject<Data, Never>()

    func send(_ packet: WormholePacket) async throws {
        logger.debug("SEND \(packet.payloadType)")

        let data = try packet.encoded()

        outboundPacketSubject.send(data)
    }

    func connect(using fileDescriptor: Int32, invalidationHandler: @escaping (WHInAppGuestConnection) -> Void) async throws {
        self.invalidationHandler = invalidationHandler

        channel = try await ClientBootstrap(group: self.eventLoopGroup)
            .channelInitializer { [weak self] channel in
                channel.eventLoop.makeCompletedFuture {
                    let upgrader = NIOTypedWebSocketClientUpgrader<UpgradeResult>(
                        upgradePipelineHandler: { (channel, _) in
                            channel.eventLoop.makeCompletedFuture {
                                let asyncChannel = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
                                return UpgradeResult.websocket(asyncChannel)
                            }
                        }
                    )

                    var headers = HTTPHeaders()
                    headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                    headers.add(name: "Content-Length", value: "0")

                    let requestHead = HTTPRequestHead(
                        version: .http1_1,
                        method: .GET,
                        uri: "/",
                        headers: headers
                    )

                    let clientUpgradeConfiguration = NIOTypedHTTPClientUpgradeConfiguration(
                        upgradeRequestHead: requestHead,
                        upgraders: [upgrader],
                        notUpgradingCompletionHandler: { channel in
                            channel.eventLoop.makeCompletedFuture {
                                return UpgradeResult.notUpgraded
                            }
                        }
                    )

                    let negotiationResultFuture = try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                        configuration: .init(upgradeConfiguration: clientUpgradeConfiguration)
                    )

                    let upgradeResult: EventLoopFuture<UpgradeResult> = negotiationResultFuture

                    guard let self else { return }

                    Task {
                        do {
                            try await self.handleUpgradeResult(upgradeResult)
                        } catch {
                            self.logger.error("handleUpgradeResult failed: \(error, privacy: .public)")
                        }
                    }
                }
            }
            .withConnectedSocket(fileDescriptor)
            .get()
    }

    private enum UpgradeResult {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
        case notUpgraded
    }

    /// This method handles the upgrade result.
    private func handleUpgradeResult(_ upgradeResult: EventLoopFuture<UpgradeResult>) async throws {
        switch try await upgradeResult.get() {
        case .websocket(let websocketChannel):
            logger.info("Handling websocket connection")

            try await self.handleWebsocketChannel(websocketChannel)

            logger.log("WebSocket connection closed")

            invalidate()
        case .notUpgraded:
            // The upgrade to websocket did not succeed. We are just exiting in this case.
            logger.info("Upgrade declined")
        }
    }

    private func handleWebsocketChannel(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
        let pingFrame = WebSocketFrame(fin: true, opcode: .ping, data: ByteBuffer(string: "Hello!"))
        
        try await channel.executeThenClose { [weak self] inbound, outbound in
            guard let self else { return }

            try await outbound.write(pingFrame)

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await packet in self.outboundPacketSubject.values {
                        self.logger.log("PACKET!")

                        do {
                            let buffer = channel.channel.allocator.buffer(bytes: packet)
                            let frame = WebSocketFrame(fin: true, opcode: .binary, data: buffer)

                            try await outbound.write(frame)
                        } catch {
                            self.logger.error("Outbound write failed: \(error, privacy: .public)")
                        }
                    }
                }
                
                group.addTask {
                    for try await frame in inbound {
                        switch frame.opcode {
                        case .pong:
                            self.logger.info("Received pong: \(String(buffer: frame.data))")

                        case .text:
                            self.logger.info("Received: \(String(buffer: frame.data))")

                        case .connectionClose:
                            // Handle a received close frame. We're just going to close by returning from this method.
                            self.logger.info("Received Close instruction from server")
                            return
                        case .binary:
                            let data = Data(buffer: frame.unmaskedData)

                            do {
                                let packet = try WormholePacket.decode(from: data)

                                self.inboundPacketSubject.send(packet)
                            } catch {
                                self.logger.warning("Packet decoding failed: \(error, privacy: .public)")
                            }
                        case .continuation, .ping:
                            // We ignore these frames.
                            break
                        default:
                            // Unknown frames are errors.
                            return
                        }
                    }
                }
                
                try await group.next()
                group.cancelAll()
            }
        }
    }

    func invalidate() {
        logger.debug(#function)

        Task {
            try? await self.channel?.close()
            self.channel = nil

            invalidationHandler?(self)
        }
    }
}
