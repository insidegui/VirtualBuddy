import Foundation
import Virtualization
import OSLog
import Combine
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

/// Connects from the host to a service running on VirtualBuddyGuest.
@available(macOS 13.0, *)
public final class WHGuestClient: ObservableObject {

    private let logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "WHGuestClient")

    private let device: VZVirtioSocketDevice
    private let port: UInt32
    private let eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    private let remote: Bool

    public init(device: VZVirtioSocketDevice, port: UInt32, remote: Bool) {
        self.device = device
        self.port = port
        self.remote = remote
    }

    private enum UpgradeResult {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
        case notUpgraded
    }

    @MainActor
    @Published public private(set) var isConnected = false

    private var connectionTask: Task<Void, Never>?
    private var currentConnection: VZVirtioSocketConnection?

    public func activate() {
        guard connectionTask == nil else { return }

        logger.debug("Activating client")

        connectionTask = Task {
            while !(await isConnected) {
                await Task.yield()

                try? await Task.sleep(nanoseconds: 5_000_000_000)

                guard !Task.isCancelled else { return }

                do {
                    logger.debug("Attempting connection...")

                    let connection = try await Task { @MainActor in try await device.connect(toPort: self.port) }.value

                    logger.debug("Connection socket opened")

                    self.currentConnection = connection

                    await MainActor.run { isConnected = true }

                    try await connect(using: connection)
                } catch {
                    logger.warning("Connection failed: \(error, privacy: .public)")

                    reset()
                }
            }
        }
    }

    private func reset() {
        Task {
            await MainActor.run { isConnected = false }

            try? await self.channel?.close()

            self.channel = nil
            self.connectionTask?.cancel()
            self.connectionTask = nil
            self.currentConnection?.close()
            self.currentConnection = nil
            self.xpcConnection = nil

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            activate()
        }
    }

    private var channel: (any Channel)?

    private func connect(using connection: VZVirtioSocketConnection) async throws {
        guard !remote else {
            connectRemote(using: connection)
            return
        }

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
            .withConnectedSocket(connection.fileDescriptor)
            .get()
    }

    /// This method handles the upgrade result.
    private func handleUpgradeResult(_ upgradeResult: EventLoopFuture<UpgradeResult>) async throws {
        switch try await upgradeResult.get() {
        case .websocket(let websocketChannel):
            logger.info("Handling websocket connection")
            
            try await self.handleWebsocketChannel(websocketChannel)
            
            logger.log("WebSocket connection closed")

            reset()
        case .notUpgraded:
            // The upgrade to websocket did not succeed. We are just exiting in this case.
            logger.info("Upgrade declined")
        }
    }

    private func handleWebsocketChannel(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
        // We are sending a ping frame and then
        // start to handle all inbound frames.

        let pingFrame = WebSocketFrame(fin: true, opcode: .ping, data: ByteBuffer(string: "Hello!"))
        try await channel.executeThenClose { inbound, outbound in
            try await outbound.write(pingFrame)

            for try await frame in inbound {
                switch frame.opcode {
                case .pong:
                    logger.info("Received pong: \(String(buffer: frame.data))")

                case .text:
                    logger.info("Received: \(String(buffer: frame.data))")

                case .connectionClose:
                    // Handle a received close frame. We're just going to close by returning from this method.
                    logger.info("Received Close instruction from server")
                    return
                case .binary, .continuation, .ping:
                    // We ignore these frames.
                    break
                default:
                    // Unknown frames are errors.
                    return
                }
            }
        }
    }

    // MARK: - Remote Client

    private var xpcConnection: xpc_connection_t?

    private func connectRemote(using vmConnection: VZVirtioSocketConnection) {
        logger.debug("Connecting remote")

        let connection = xpc_connection_create_mach_service("codes.rambo.wormholeconnection", .main, 0)
        self.xpcConnection = connection

        xpc_connection_set_event_handler(connection) { [weak self] message in
            guard let self else { return }

            if xpc_get_type(message) == XPC_TYPE_ERROR {
                logger.warning("XPC connection error: \(xpc_description(message))")
                reset()
            } else {
                logger.warning("Unhandled XPC message: \(xpc_description(message))")
            }
        }

        xpc_connection_activate(connection)

        let fd = xpc_fd_create(vmConnection.fileDescriptor)

        let dict = xpc_dictionary_create_empty()
        xpc_dictionary_set_uint64(dict, "action", 0)
        xpc_dictionary_set_value(dict, "fd", fd)

        logger.debug("Sending connection message to remote service")

        xpc_connection_send_message(connection, dict)
    }

}

private func xpc_description(_ obj: xpc_object_t) -> String {
    String(cString: xpc_copy_description(obj))
}

private final class EchoHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    private var sendBytes = 0
    private var receiveBuffer: ByteBuffer = ByteBuffer()

    public func channelActive(context: ChannelHandlerContext) {
        print("Client connected to \(context.remoteAddress?.description ?? "unknown")")

        // We are connected. It's time to send the message to the server to initialize the ping-pong sequence.
        let buffer = context.channel.allocator.buffer(string: "ping")
        self.sendBytes = buffer.readableBytes
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var unwrappedInboundData = self.unwrapInboundIn(data)
        self.sendBytes -= unwrappedInboundData.readableBytes
        receiveBuffer.writeBuffer(&unwrappedInboundData)

        if self.sendBytes == 0 {
            let string = String(buffer: receiveBuffer)
            print("Received: '\(string)' back from the server.")
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }
}
