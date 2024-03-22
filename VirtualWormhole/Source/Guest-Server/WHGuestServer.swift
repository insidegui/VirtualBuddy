import Foundation
import OSLog
import Combine
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

typealias HTTPChannel = NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>
typealias WebSocketChannel = NIOAsyncChannel<WebSocketFrame, WebSocketFrame>

/// Handles the underlying WebSocket server for VirtualBuddyGuest.
/// Service implementations use an instance of `WHGuestServer` in order to publish the service to the host.
final class WHGuestServer {
    let id: String
    private let port: VsockAddress.Port
    private let logger: Logger
    
    init(id: String, port: VsockAddress.Port) {
        self.id = id
        self.port = port
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "WHGuestServer(\(id))")
    }

    private let eventLoopGroup = MultiThreadedEventLoopGroup.singleton

    private static let responseBody = ByteBuffer(string: "")

    enum UpgradeResult {
        case websocket(WebSocketChannel)
        case notUpgraded(HTTPChannel)
    }
    
    private var serverTask: Task<Void, Never>?
    private var onConnect: ((WHGuestServer) -> Void)?
    private var onDisconnect: ((WHGuestServer) -> Void)?
    
    func activate(onConnect: @escaping (WHGuestServer) -> Void, onDisconnect: @escaping (WHGuestServer) -> Void) {
        serverTask?.cancel()

        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        
        serverTask = Task {
            do {
                try await run()
            } catch {
                logger.error("Server error: \(error, privacy: .public)")
                
                self.onDisconnect?(self)
            }
        }
    }

    /// Produces a new element for each packet received from the connected client.
    var packets: AnyPublisher<WormholePacket, Never> { inboundPacketSubject.eraseToAnyPublisher() }
    private let inboundPacketSubject = PassthroughSubject<WormholePacket, Never>()
    
    /// Elements from this subject are sent to the connected client.
    private let outboundPacketSubject = PassthroughSubject<Data, Never>()
    
    func send(_ packet: WormholePacket) async throws {
        let data = try packet.encoded()
        
        outboundPacketSubject.send(data)
    }
    
    func invalidate() {
        serverTask?.cancel()
        serverTask = nil
    }

    private func run() async throws {
        logger.debug(#function)
        
        let channel: NIOAsyncChannel<EventLoopFuture<UpgradeResult>, Never> = try await ServerBootstrap(group: self.eventLoopGroup)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .bind(to: VsockAddress(cid: .any, port: port)) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let upgrader = NIOTypedWebSocketServerUpgrader<UpgradeResult>(
                        shouldUpgrade: { (channel, head) in
                            channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                        },
                        upgradePipelineHandler: { (channel, _) in
                            channel.eventLoop.makeCompletedFuture {
                                let asyncChannel = try WebSocketChannel(wrappingChannelSynchronously: channel)
                                return UpgradeResult.websocket(asyncChannel)
                            }
                        }
                    )

                    let serverUpgradeConfiguration = NIOTypedHTTPServerUpgradeConfiguration(
                        upgraders: [upgrader],
                        notUpgradingCompletionHandler: { channel in
                            channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(HTTPByteBufferResponsePartHandler())
                                let asyncChannel = try HTTPChannel(wrappingChannelSynchronously: channel)
                                return UpgradeResult.notUpgraded(asyncChannel)
                            }
                        }
                    )

                    let negotiationResultFuture = try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(
                        configuration: .init(upgradeConfiguration: serverUpgradeConfiguration)
                    )

                    return negotiationResultFuture
                }
            }

        // We are handling each incoming connection in a separate child task. It is important
        // to use a discarding task group here which automatically discards finished child tasks.
        // A normal task group retains all child tasks and their outputs in memory until they are
        // consumed by iterating the group or by exiting the group. Since, we are never consuming
        // the results of the group we need the group to automatically discard them; otherwise, this
        // would result in a memory leak over time.
        try await withThrowingTaskGroup(of: Void.self) { group in
            try await channel.executeThenClose { inbound in
                for try await upgradeResult in inbound {
                    group.addTask {
                        await self.handleUpgradeResult(upgradeResult)
                    }
                }
            }
            
            try await group.next()
            group.cancelAll()
        }
    }

    /// This method handles a single connection by echoing back all inbound data.
    private func handleUpgradeResult(_ upgradeResult: EventLoopFuture<UpgradeResult>) async {
        // Note that this method is non-throwing and we are catching any error.
        // We do this since we don't want to tear down the whole server when a single connection
        // encounters an error.
        do {
            switch try await upgradeResult.get() {
            case .websocket(let websocketChannel):
                logger.log("Handling websocket connection")
                
                self.onConnect?(self)
                
                try await self.handleWebsocketChannel(websocketChannel)
                
                logger.log("Done handling websocket connection")
                
                self.onDisconnect?(self)
            case .notUpgraded(let httpChannel):
                logger.log("Handling HTTP connection")
                
                self.onConnect?(self)
                
                try await self.handleHTTPChannel(httpChannel)
                
                logger.log("Done handling HTTP connection")
            }
        } catch {
            logger.log("Hit error: \(error, privacy: .public)")
            
            self.onDisconnect?(self)
        }
    }

    private func handleWebsocketChannel(_ channel: WebSocketChannel) async throws {
        try await channel.executeThenClose { [weak self] inbound, outbound in
            guard let self else { return }
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await frame in inbound {
                        switch frame.opcode {
                        case .ping:
                            self.logger.log("Received ping")
                            var frameData = frame.data
                            let maskingKey = frame.maskKey

                            if let maskingKey = maskingKey {
                                frameData.webSocketUnmask(maskingKey)
                            }

                            let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
                            try await outbound.write(responseFrame)

                        case .connectionClose:
                            // This is an unsolicited close. We're going to send a response frame and
                            // then, when we've sent it, close up shop. We should send back the close code the remote
                            // peer sent us, unless they didn't send one at all.
                            self.logger.log("Received close")
                            var data = frame.unmaskedData
                            let closeDataCode = data.readSlice(length: 2) ?? ByteBuffer()
                            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
                            try await outbound.write(closeFrame)
                            return
                        case .binary:
                            let data = Data(buffer: frame.unmaskedData)
                            
                            do {
                                let packet = try WormholePacket.decode(from: data)
                                
                                self.inboundPacketSubject.send(packet)
                            } catch {
                                self.logger.warning("Packet decoding failed: \(error, privacy: .public)")
                            }
                        case .continuation, .pong:
                            // We ignore these frames.
                            break
                        default:
                            // Unknown frames are errors.
                            return
                        }
                    }
                }
                
                /// Stream outbound packets, writing them to the channel.
                group.addTask {
                    for await packet in self.outboundPacketSubject.values {
                        do {
                            let buffer = channel.channel.allocator.buffer(bytes: packet)
                            let frame = WebSocketFrame(fin: true, opcode: .binary, data: buffer)
                            
                            try await outbound.write(frame)
                        } catch {
                            self.logger.error("Outbound write failed: \(error, privacy: .public)")
                        }
                    }
                }

//                group.addTask {
//                    // This is our main business logic where we are just sending the current time
//                    // every second.
//                    while true {
//                        // We can't really check for error here, but it's also not the purpose of the
//                        // example so let's not worry about it.
//                        let theTime = ContinuousClock().now
//                        var buffer = channel.channel.allocator.buffer(capacity: 12)
//                        buffer.writeString("\(theTime)")
//
//                        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
//
//                        self.logger.log("Sending time")
//                        try await outbound.write(frame)
//                        try await Task.sleep(for: .seconds(1))
//                    }
//                }

                try await group.next()
                group.cancelAll()
            }
        }
    }

    private func handleHTTPChannel(_ channel: HTTPChannel) async throws {
        try await channel.executeThenClose { inbound, outbound in
            for try await requestPart in inbound {
                // We're not interested in request bodies here: we're just serving up GET responses
                // to get the client to initiate a websocket request.
                guard case .head(let head) = requestPart else {
                    return
                }

                // GETs only.
                guard case .GET = head.method else {
                    try await self.respond405(writer: outbound)
                    return
                }

                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: "text/html")
                headers.add(name: "Content-Length", value: String(Self.responseBody.readableBytes))
                headers.add(name: "Connection", value: "close")
                let responseHead = HTTPResponseHead(
                    version: .init(major: 1, minor: 1),
                    status: .ok,
                    headers: headers
                )

                try await outbound.write(
                    contentsOf: [
                        .head(responseHead),
                        .body(Self.responseBody),
                        .end(nil)
                    ]
                )
            }
        }
    }

    private func respond405(writer: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
        var headers = HTTPHeaders()
        headers.add(name: "Connection", value: "close")
        headers.add(name: "Content-Length", value: "0")
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .methodNotAllowed,
            headers: headers
        )

        try await writer.write(
            contentsOf: [
                .head(head),
                .end(nil)
            ]
        )
    }
}

final class HTTPByteBufferResponsePartHandler: ChannelOutboundHandler {
    typealias OutboundIn = HTTPPart<HTTPResponseHead, ByteBuffer>
    typealias OutboundOut = HTTPServerResponsePart

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let part = self.unwrapOutboundIn(data)
        switch part {
        case .head(let head):
            context.write(self.wrapOutboundOut(.head(head)), promise: promise)
        case .body(let buffer):
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: promise)
        case .end(let trailers):
            context.write(self.wrapOutboundOut(.end(trailers)), promise: promise)
        }
    }
}

extension Data {
    init(buffer: ByteBuffer) {
        self.init([UInt8].init(buffer: buffer))
    }
}
