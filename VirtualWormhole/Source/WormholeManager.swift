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

public final class WormholeManager: NSObject, ObservableObject, VZVirtioSocketListenerDelegate, WormholeMultiplexer {

    /// Singleton manager used by the VirtualBuddy app to talk
    /// to VirtualBuddyGuest running in virtual machines.
    public static let sharedHost = WormholeManager(for: .host)

    /// Singleton manager used by the VirtualBuddyGuest app in a virtual machine
    /// to talk to VirtualBuddy running in the host.
    public static let sharedGuest = WormholeManager(for: .guest)

    @Published private(set) var peers = [WHPeerID: WormholeChannel]()

    @Published public private(set) var isConnected = false
    
    public enum Side: Hashable, CustomStringConvertible {
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
    
    private lazy var logger = Logger(for: Self.self)

    let serviceTypes: [WormholeService.Type] = [
        WHSharedClipboardService.self
    ]
    
    var activeServices: [WormholeService] = []
    
    let side: Side
    
    public init(for side: Side) {
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

        $peers
            .map { !$0.isEmpty }
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        #if DEBUG
        $peers.removeDuplicates(by: { $0.keys != $1.keys }).sink { [weak self] currentPeers in
            guard let self = self else { return }
            self.logger.debug("Peers: \(currentPeers.keys.joined(separator: ", "), privacy: .public)")
        }
        .store(in: &cancellables)
        #endif
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

    // MARK: - Guest Mode

    private var hostOutputHandle: FileHandle {
        get throws {
            try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/cu.virtio"))
        }
    }

    private var hostInputHandle: FileHandle {
        get throws {
            try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/cu.virtio"))
        }
    }

    private func activateGuestIfNeeded() async throws {
        guard side == .guest else { return }

        logger.debug("Running in guest mode, registering host peer")

        let input = try hostOutputHandle
        let output = try hostInputHandle

        await register(input: input, output: output, for: .host)
    }

}

// MARK: - Channel Actor

actor WormholeChannel {

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

    func invalidate() {
        guard activated else { return }
        activated = false

        logger.debug(#function)

        streamingTask?.cancel()
    }

    func send(_ packet: WormholePacket) async throws {
        let data = packet.encoded()

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "WHLogPacketContents") {
            logger.debug("\(data.map({ String(format: "%02X", $0) }).joined(), privacy: .public)")
        }
        #endif

        try output.write(contentsOf: data)
    }

    private var streamingTask: Task<Void, Never>?

    private func stream() {
        logger.debug(#function)

        streamingTask = Task {
            do {
                for try await packet in WormholePacket.stream(from: input.bytes) {
                    logger.debug("Got packet: \(String(describing: packet), privacy: .public)")
                    
                    guard !Task.isCancelled else { break }

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

}
