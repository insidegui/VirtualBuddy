//
//  WormholeManager.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization
import OSLog
import Combine

public typealias WHPeerID = String

public extension WHPeerID {
    static let host = "Host"
}

public enum WHConnectionSide: Hashable, CustomStringConvertible {
    case host
    case guest

    public var description: String {
        switch self {
        case .host:
            return "Host"
        case .guest:
            return "Guest"
        }
    }
}

public final class WormholeManager: NSObject, ObservableObject, WormholeMultiplexer {

    struct ChannelToken: Hashable {
        var peerID: WHPeerID
        var serviceID: String
    }

    /// Singleton manager used by the VirtualBuddy app to talk
    /// to VirtualBuddyGuest running in virtual machines.
    public static let sharedHost = WormholeManager(for: .host)

    /// Singleton manager used by the VirtualBuddyGuest app in a virtual machine
    /// to talk to VirtualBuddy running in the host.
    public static let sharedGuest = WormholeManager(for: .guest)

    @Published private(set) var channels = [ChannelToken: WormholeChannel]()

    @Published public private(set) var isConnected = false

    fileprivate lazy var logger = Logger(for: Self.self)

    let serviceTypes: [WormholeService.Type] = [
        WHControlService.self,
        WHSharedClipboardService.self,
//        WHDarwinNotificationsService.self,
//        WHDefaultsImportService.self
    ]
    
    var activeServices: [WormholeService] = []

    public let side: WHConnectionSide
    
    public init(for side: WHConnectionSide) {
        self.side = side

        super.init()
    }

    public func makeClient<C: WormholeServiceClient>(_ type: C.Type) throws -> C {
        guard let service = activeServices.compactMap({ $0 as? C.ServiceType }).first else {
            throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Service unavailable."])
        }
        return C(with: service)
    }

    private var activated = false

    private lazy var cancellables = Set<AnyCancellable>()

    public func activate() {
        guard !activated else { return }
        activated = true
        
        logger.debug("Activate side \(String(describing: self.side))")

        Task {
            do {
                try await activateGuestIfNeeded()
            } catch {
                logger.fault("Failed to register host peer: \(error, privacy: .public)")
            }
        }

        activeServices = serviceTypes
            .map { $0.init(with: self) }
        activeServices.forEach { $0.activate() }

        #if DEBUG
        $channels.removeDuplicates(by: { $0.keys != $1.keys }).sink { [weak self] currentPeers in
            guard let self = self else { return }
            self.logger.debug("Peers: \(currentPeers.keys.map(\.peerID).joined(separator: ", "), privacy: .public)")
        }
        .store(in: &cancellables)
        #endif
    }

    private let packetSubject = PassthroughSubject<(token: ChannelToken, packet: WormholePacket), Never>()

    func createChannel<S: WormholeService>(with transport: WormholeChannel.Transport, forServiceType serviceType: S.Type, peerID: WHPeerID) async {
        let token = ChannelToken(peerID: peerID, serviceID: serviceType.id)

        if let existing = channels[token] {
            await existing.invalidate()
        }

        let channel = await WormholeChannel(
            serviceType: serviceType,
            peerID: peerID,
            transport: transport
        ).onPacketReceived { [weak self] senderID, packet in
            guard let self = self else { return }
            self.packetSubject.send((ChannelToken(peerID: senderID, serviceID: S.id), packet))
        }

        /// When running in guest mode, observe the channel's connection state and bind it to the manager's state.
        if self.side == .guest {
            await channel.$isConnected.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] isConnected in
                guard let self = self else { return }
                self.logger.notice("Connection to host changed state (isConnected = \(isConnected, privacy: .public))")
                self.isConnected = isConnected
            }.store(in: &cancellables)
        }

        channels[token] = channel

        await channel.activate()
    }

    public func unregister(_ peerID: WHPeerID) async {
        let peerChannels = channels.filter({ $0.key.peerID == peerID })

        for (token, channel) in peerChannels {
            await channel.invalidate()
            channels[token] = nil
        }
    }

    public func send<T: WHPayload>(_ payload: T, to peerID: WHPeerID?) async {
        guard !channels.isEmpty else { return }
        
        if side == .guest {
            guard peerID == nil || peerID == .host else {
                logger.fault("Guest can only send messages to host!")
                assertionFailure("Guest can only send messages to host!")
                return
            }
        }

        let serviceID = T.serviceType.id

        do {
            let packet = try WormholePacket(payload)

            if let peerID {
                let token = ChannelToken(peerID: peerID, serviceID: serviceID)

                guard let channel = channels[token] else {
                    logger.error("Couldn't find channel for \(serviceID) on peer \(peerID)")
                    return
                }

                /// Message will be repeated if other side disconnects and reconnects.
                if T.resendOnReconnect {
                    await channel.connected {
                        do {
                            /// Make sure there's a fresh packet every time the message is sent.
                            let newPacket = try WormholePacket(payload)

                            try await $0.send(newPacket)
                        } catch {
                            assertionFailure("Failed to send packet: \(error)")
                        }
                    }
                } else {
                    try await channel.send(packet)
                }
            } else {
                for (token, channel) in channels where token.serviceID == T.Service.id {
                    try await channel.send(packet)
                }
            }
        } catch {
            logger.warning("Failed to send \(serviceID, privacy: .public) packet: \(error, privacy: .public)")
        }
    }

    public func stream<T: WHPayload>(for payloadType: T.Type) -> AsyncThrowingStream<(senderID: WHPeerID, payload: T), Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            let typeName = String(describing: payloadType)

            let cancellable = self.packetSubject
                .filter { $0.packet.payloadType == typeName && $0.token.serviceID == T.Service.id }
                .sink { [weak self] token, packet in
                    guard let self = self else { return }

                    guard let decodedPayload = try? JSONDecoder.wormhole.decode(payloadType, from: packet.payload) else { return }

                    self.propagateIfNeeded(packet, type: payloadType, from: token.peerID)

                    continuation.yield((token.peerID, decodedPayload))
                }

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }

    private func propagateIfNeeded<P: WHPayload>(_ packet: WormholePacket, type: P.Type, from senderID: WHPeerID) {
        guard type.propagateBetweenGuests, VirtualWormholeConstants.payloadPropagationEnabled else { return }

        let propagationChannels = self.channels.filter({ $0.key.peerID != senderID && $0.key.serviceID == P.serviceType.id })

        Task {
            for (token, channel) in propagationChannels {
                do {
                    if VirtualWormholeConstants.verboseLoggingEnabled {
                        logger.debug("⬆️ PROPAGATE \(packet.payloadType, privacy: .public) from \(senderID, privacy: .public) to \(token.peerID, privacy: .public)")
                    }
                    try await channel.send(packet)
                } catch {
                    logger.error("Packet propagation to \(token.peerID, privacy: .public) failed: \(error, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Ping

    /// Waits for a connection with the given peer.
    private func wait(for peerID: WHPeerID, serviceID: String? = nil) async {
        let token = ChannelToken(peerID: peerID, serviceID: serviceID ?? WHControlService.id)

        guard let channel = channels[token] else {
            logger.error("Can't wait for service \(token.serviceID) on peer \(peerID) for which a channel doesn't exist")
            return
        }

        guard await channel.isConnected == false else { return }

        for await state in await channel.$isConnected.values {
            guard state else { continue }
            break
        }
    }

    /// Performs the specified asynchronous closure whenever the connection state for the peer changes
    /// from not connected to connected. Also runs the closure if peer is already connected at the time of calling.
    private func connected(to peerID: WHPeerID, serviceID: String? = nil, perform block: @escaping (WormholeChannel) async -> Void) async {
        let token = ChannelToken(peerID: peerID, serviceID: serviceID ?? WHControlService.id)

        guard let channel = channels[token] else {
            logger.error("Can't wait for service \(token.serviceID) on peer \(peerID) for which a channel doesn't exist")
            return
        }

        await channel.connected(perform: block)
    }

    // MARK: - Service Interfaces

    private func service<T: WormholeService>(_ serviceType: T.Type) -> T? {
        activeServices.first(where: { type(of: $0).id == serviceType.id }) as? T
    }

    public func darwinNotifications(matching names: Set<String>, from peerID: WHPeerID) async throws -> AsyncStream<String> {
        let token = ChannelToken(peerID: peerID, serviceID: WHDarwinNotificationsService.id)

        guard channels[token] != nil else {
            throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "Peer \(peerID) is not registered"])
        }
        guard let notificationService = service(WHDarwinNotificationsService.self) else {
            throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "Darwin notifications service not available"])
        }

        try Task.checkCancellation()

        for name in names {
            await send(DarwinNotificationMessage.subscribe(name), to: peerID)
        }

        var iterator = notificationService.onPeerNotificationReceived.values
            .filter { $0.peerID == peerID }
            .map(\.name)
            .makeAsyncIterator()

        return AsyncStream { await iterator.next() }
    }

    // MARK: - Guest Mode

    private func activateGuestIfNeeded() async throws {
        guard side == .guest else { return }

        logger.debug("Running in guest mode, registering host peer")

        for serviceType in serviceTypes {
            do {
                let socket = try WHSocket(hostPort: serviceType.port)
                await createChannel(with: .socket(socket), forServiceType: serviceType, peerID: .host)
            } catch {
                logger.error("Channel registration failed for \(serviceType, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

}

// MARK: - Channel Actor

actor WormholeChannel: NSObject, ObservableObject, VZVirtioSocketListenerDelegate {

    enum Transport {
        case socket(WHSocket)
        case listener(VZVirtioSocketListener)
    }

    let serviceID: String
    let peerID: WHPeerID
    private var socket: WHSocket?
    private var listener: VZVirtioSocketListener?
    private let logger: Logger

    init<Service: WormholeService>(serviceType: Service.Type, peerID: WHPeerID, transport: Transport) {
        self.serviceID = serviceType.id
        self.peerID = peerID
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "WormholeChannel-\(peerID)-\(serviceType.id)")
        
        switch transport {
        case .socket(let socket):
            self.socket = socket
        case .listener(let listener):
            self.listener = listener
        }

        super.init()

        self.listener?.delegate = self
    }

    @Published private(set) var isConnected = false {
        didSet {
            guard isConnected != oldValue else { return }
            logger.debug("isConnected = \(self.isConnected, privacy: .public)")
        }
    }

    private let packetSubject = PassthroughSubject<WormholePacket, Never>()

    private var heartbeatCancellable: AnyCancellable?

    private lazy var cancellables = Set<AnyCancellable>()

    @discardableResult
    func onPacketReceived(perform block: @escaping (WHPeerID, WormholePacket) -> Void) -> Self {
        packetSubject.sink { [weak self] packet in
            guard let self = self else { return }

            block(self.peerID, packet)
        }
        .store(in: &cancellables)

        return self
    }

    private var activated = false

    func activate() {
        guard !activated else { return }
        activated = true

        logger.debug(#function)

        if let socket {
            stream(socket)
        }
    }

    func invalidate() {
        guard activated else { return }
        activated = false

        logger.debug(#function)

        cancellables.removeAll()

        timeoutTask?.cancel()
        timeoutTask = nil

        heartbeatCancellable?.cancel()
        heartbeatCancellable = nil

        internalTasks.forEach { $0.cancel() }
        internalTasks.removeAll()
    }

    func send(_ packet: WormholePacket) async throws {
        guard let socket else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Socket not available yet"])
        }
        let data = try packet.encoded()

        if VirtualWormholeConstants.verboseLoggingEnabled {
            if packet.isHeartbeat, VirtualWormholeConstants.verboseLoggingEnabledHeartbeat {
                logger.debug("💓 SEND HEARTBEAT")
            } else {
                logger.debug("⬆️ SEND \(packet.payloadType, privacy: .public) (\(packet.payload.count) bytes)")
                logger.debug("⏫ \(data.map({ String(format: "%02X", $0) }).joined(), privacy: .public)")
            }
        }

        try socket.write(data)

        if VirtualWormholeConstants.verboseLoggingEnabled {
            if !packet.isHeartbeat {
                logger.debug("⬆️✅ SENT \(packet.payloadType, privacy: .public) (\(packet.payload.count) bytes)")
            }
        }
    }

    private var internalTasks = [Task<Void, Never>]()

    private func stream(_ socket: WHSocket) {
        logger.debug(#function)

        self.isConnected = true
        self.socket = socket

        let streamingTask = Task {
            do {
                for try await packet in WormholePacket.stream(from: socket.bytes) {
                    if packet.isHeartbeat, VirtualWormholeConstants.verboseLoggingEnabledHeartbeat {
                        logger.debug("💓 RECEIVED HEARTBEAT")
                    } else {
                        logger.debug("⬇️ RECEIVE \(packet.payloadType, privacy: .public) (\(packet.payload.count) bytes)")
                        logger.debug("⏬ \(packet.payload.map({ String(format: "%02X", $0) }).joined(), privacy: .public)")
                    }
                    
                    guard !Task.isCancelled else { break }

                    guard !packet.isHeartbeat else {
                        await handleHeartbeat(packet)
                        continue
                    }

                    packetSubject.send(packet)
                }

                logger.debug("⬇️ Packet streaming cancelled")
            } catch {
                logger.error("⬇️ Read failure: \(error, privacy: .public)")

                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)

                guard !Task.isCancelled else { return }

                stream(socket)
            }
        }
        internalTasks.append(streamingTask)
    }

    private func startHeartbeatIfNeeded() {
        guard socket != nil else {
            self.logger.warning("Skipping heartbeat start: socket not available yet")
            return
        }

        guard heartbeatCancellable == nil else { return }

        heartbeatCancellable = Timer
            .publish(every: VirtualWormholeConstants.pingIntervalInSeconds, tolerance: VirtualWormholeConstants.pingIntervalInSeconds * 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }

                Task {
                    do {
                        try await self.send(.heartbeat)
                    } catch {
                        self.logger.warning("Failed to send heartbeat: \(error, privacy: .public)")
                    }
                }
            }
    }

    private var timeoutTask: Task<Void, Never>?

    private func handleHeartbeat(_ packet: WormholePacket) async {
        self.isConnected = true

        timeoutTask?.cancel()

        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: VirtualWormholeConstants.connectionTimeoutInNanoseconds)

            guard !Task.isCancelled else { return }

            logger.debug("💓 Connection timeout")

            self.isConnected = false
        }
    }

    func connected(perform block: @escaping (WormholeChannel) async -> Void) {
        let task = Task { [weak self] in
            guard let self = self else { return }

            for await state in await self.$isConnected.removeDuplicates().values {
                if state {
                    await block(self)
                }
            }
        }
        internalTasks.append(task)
    }

    nonisolated func listener(_ listener: VZVirtioSocketListener, shouldAcceptNewConnection connection: VZVirtioSocketConnection, from socketDevice: VZVirtioSocketDevice) -> Bool {
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)

            let socket = WHSocket(connection: connection)

            logger.debug("Listener socket opened")

            await stream(socket)
        }
        return true
    }

}

extension WormholeManager: VZVirtioSocketListenerDelegate {

    /// Registers socket listeners
    public func addServiceListeners(to machine: VZVirtualMachine, peerID: WHPeerID) async {
        guard let socketDevice = machine.socketDevices.first as? VZVirtioSocketDevice else {
            logger.fault("Can't add service listeners to VM without a socket device")
            return
        }

        for serviceType in self.serviceTypes {
            let listener = await MainActor.run {
                let listener = VZVirtioSocketListener()
                socketDevice.setSocketListener(listener, forPort: serviceType.port)
                return listener
            }
            await createChannel(with: .listener(listener), forServiceType: serviceType, peerID: peerID)
        }
    }

}
