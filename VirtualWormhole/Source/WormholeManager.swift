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

public final class WormholeManager: NSObject, ObservableObject, VZVirtioSocketListenerDelegate, WormholeMultiplexer {

    /// Singleton manager used by the VirtualBuddy app to talk
    /// to VirtualBuddyGuest running in virtual machines.
    public static let sharedHost = WormholeManager(for: .host)

    /// Singleton manager used by the VirtualBuddyGuest app in a virtual machine
    /// to talk to VirtualBuddy running in the host.
    public static let sharedGuest = WormholeManager(for: .guest)

    @Published private(set) var peers = [WHPeerID: WormholeChannel]()

    @Published public private(set) var isConnected = false

    private lazy var logger = Logger(for: Self.self)

    let serviceTypes: [WormholeService.Type] = [
        WHSharedClipboardService.self,
        WHDarwinNotificationsService.self,
        WHDefaultsImportService.self
    ]
    
    var activeServices: [WormholeService] = []
    
    let side: WHConnectionSide
    
    public init(for side: WHConnectionSide) {
        self.side = side

        super.init()
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
                assertionFailure("Failed to register host peer: \(error)")
            }
        }

        activeServices = serviceTypes
            .map { $0.init(with: self) }
        activeServices.forEach { $0.activate() }

        #if DEBUG
        $peers.removeDuplicates(by: { $0.keys != $1.keys }).sink { [weak self] currentPeers in
            guard let self = self else { return }
            self.logger.debug("Peers: \(currentPeers.keys.joined(separator: ", "), privacy: .public)")
        }
        .store(in: &cancellables)
        #endif

        Timer
            .publish(every: 3, tolerance: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }

                Task {
                    await self.send(WHPing(), to: nil)
                }
            }
            .store(in: &cancellables)
    }

    private let packetSubject = PassthroughSubject<(peerID: WHPeerID, packet: WormholePacket), Never>()

    public func register(input: FileHandle, output: FileHandle, for peerID: WHPeerID) async {
        if let existing = peers[peerID] {
            await existing.invalidate()
        }

        let channel = await WormholeChannel(
            input: input,
            output: output,
            peerID: peerID
        ).onPacketReceived { [weak self] senderID, packet in
            guard let self = self else { return }
            self.packetSubject.send((senderID, packet))
        }

        peers[peerID] = channel

        await channel.activate()
    }

    public func unregister(_ peerID: WHPeerID) async {
        guard let channel = peers[peerID] else { return }

        await channel.invalidate()

        peers[peerID] = nil
    }

    func send<T: Codable>(_ payload: T, to peerID: WHPeerID?) async {
        guard !peers.isEmpty else { return }
        
        if side == .guest {
            guard peerID == nil || peerID == .host else {
                logger.fault("Guest can only send messages to host!")
                assertionFailure("Guest can only send messages to host!")
                return
            }
        }

        do {
            let packet = try WormholePacket(payload)

            if let peerID {
                guard let channel = peers[peerID] else {
                    logger.error("Couldn't find channel for peer \(peerID)")
                    return
                }

                try await channel.send(packet)
            } else {
                for channel in peers.values {
                    try await channel.send(packet)
                }
            }
        } catch {
            logger.fault("Failed to encode packet: \(error, privacy: .public)")
            assertionFailure("Failed to encode packet: \(error)")
        }
    }

    func stream<T: Codable>(for payloadType: T.Type) -> AsyncThrowingStream<(senderID: WHPeerID, payload: T), Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            let typeName = String(describing: payloadType)

            let cancellable = self.packetSubject
                .filter { $0.packet.payloadType == typeName }
                .sink { peerID, packet in
                    guard let decodedPayload = try? JSONDecoder().decode(payloadType, from: packet.payload) else { return }

                    continuation.yield((peerID, decodedPayload))
                }

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }

    // MARK: - Ping

    /// Waits for a connection with the given peer.
    private func wait(for peerID: WHPeerID) async {
        guard let channel = peers[peerID] else {
            logger.error("Can't wait for peer \(peerID) for which a channel doesn't exist")
            return
        }

        guard await channel.isConnected == false else { return }

        for await state in await channel.$isConnected.values {
            guard state else { continue }
            break
        }
    }

    // MARK: - Service Interfaces

    private func service<T: WormholeService>(_ serviceType: T.Type) -> T? {
        activeServices.first(where: { type(of: $0).id == serviceType.id }) as? T
    }

    public func darwinNotifications(matching names: Set<String>, from peerID: WHPeerID) async throws -> AsyncStream<String> {
        guard peers[peerID] != nil else {
            throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "Peer \(peerID) is not registered"])
        }
        guard let notificationService = service(WHDarwinNotificationsService.self) else {
            throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "Darwin notifications service not available"])
        }

        await wait(for: peerID)

        try Task.checkCancellation()

        for name in names {
            await send(DarwinNotificationMessage.subscribe(name), to: peerID)
        }

        try Task.checkCancellation()

        return AsyncStream { continuation in
            let cancellable = notificationService.onPeerNotificationReceived
                .filter { $0.peerID == peerID }
                .sink { name, _ in
                    continuation.yield(name)
                }

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }

    // MARK: - Guest Mode

    private let ttyPath = "/dev/cu.virtio"

    private var hostOutputHandle: FileHandle {
        get throws {
            try FileHandle(forReadingFrom: URL(fileURLWithPath: ttyPath))
        }
    }

    private var hostInputHandle: FileHandle {
        get throws {
            try FileHandle(forWritingTo: URL(fileURLWithPath: ttyPath))
        }
    }

    private func activateGuestIfNeeded() async throws {
        guard side == .guest else { return }

        configureTTY()

        logger.debug("Running in guest mode, registering host peer")

        let input = try hostOutputHandle
        let output = try hostInputHandle

        await register(input: input, output: output, for: .host)
    }

    private func configureTTY() {
        do {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/stty")
            proc.arguments = [
                "-f",
                ttyPath,
                "115200"
            ]
            let errPipe = Pipe()
            let outPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = outPipe

            try proc.run()
            proc.waitUntilExit()

            if let errData = try? errPipe.fileHandleForReading.readToEnd(), !errData.isEmpty {
                logger.debug("stty stdout: \(String(decoding: errData, as: UTF8.self), privacy: .public)")
            }
            if let outData = try? outPipe.fileHandleForReading.readToEnd(), !outData.isEmpty {
                logger.debug("stty stderr: \(String(decoding: outData, as: UTF8.self), privacy: .public)")
            }
        } catch {
            logger.error("stty error: \(error, privacy: .public)")
        }
    }

}

// MARK: - Channel Actor

actor WormholeChannel: ObservableObject {

    let input: FileHandle
    let output: FileHandle
    let peerID: WHPeerID
    private let logger: Logger

    init(input: FileHandle, output: FileHandle, peerID: WHPeerID) {
        self.input = input
        self.output = output
        self.peerID = peerID
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: "WormholeChannel-\(peerID)")
    }

    @Published private(set) var isConnected = false {
        didSet {
            #if DEBUG
            guard isConnected != oldValue else { return }
            logger.debug("isConnected = \(self.isConnected, privacy: .public)")
            #endif
        }
    }

    private let packetSubject = PassthroughSubject<WormholePacket, Never>()

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

        stream()
    }

    private func updateConnectionState(_ state: Bool) {
        self.isConnected = state
    }

    func invalidate() {
        guard activated else { return }
        activated = false

        logger.debug(#function)

        streamingTask?.cancel()
    }

    func send(_ packet: WormholePacket) async throws {
        let data = try packet.encoded()

        if VirtualWormholeConstants.verboseLoggingEnabled {
            logger.debug("\(data.map({ String(format: "%02X", $0) }).joined(), privacy: .public)")
        }

        try output.write(contentsOf: data)
    }

    private var streamingTask: Task<Void, Never>?

    private func stream() {
        logger.debug(#function)

        streamingTask = Task {
            do {
                for try await packet in WormholePacket.stream(from: input.bytes) {
                    if VirtualWormholeConstants.verboseLoggingEnabled {
                        logger.debug("Got packet: \(String(describing: packet), privacy: .public)")
                    }
                    
                    guard !Task.isCancelled else { break }

                    guard !packet.isPing && !packet.isPong else {
                        await handlePingPong(packet)
                        continue
                    }

                    packetSubject.send(packet)
                }

                logger.debug("Packet streaming cancelled")
            } catch {
                logger.error("Serial read failure: \(error, privacy: .public)")

                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)

                guard !Task.isCancelled else { return }

                stream()
            }
        }
    }

    private var timeoutTask: Task<Void, Never>?

    private func handlePingPong(_ packet: WormholePacket) async {
        self.isConnected = true

        if packet.isPing {
            if VirtualWormholeConstants.verboseLoggingEnabled {
                logger.debug("Received ping")
            }

            try? await send(WormholePacket(WHPong()))
        } else {
            if VirtualWormholeConstants.verboseLoggingEnabled {
                logger.debug("Received pong")
            }
        }

        timeoutTask?.cancel()

        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)

            guard !Task.isCancelled else { return }

            logger.warning("Connection timed out")

            self.isConnected = false
        }
    }

}
