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

    public func register(input: FileHandle, output: FileHandle, for peerID: WHPeerID) async {
        if let existing = peers[peerID] {
            await existing.invalidate()
        }

        let channel = WormholeChannel(input: input, output: output, peerID: peerID)

        peers[peerID] = channel

        await channel.activate()
    }

    public func unregister(_ peerID: WHPeerID) async {
        guard let channel = peers[peerID] else { return }

        await channel.invalidate()

        peers[peerID] = nil
    }

    func send<T: Codable>(_ payload: T, to peerID: WHPeerID?) {

    }

    func receive<T: Codable>(_ type: T.Type, using callback: @escaping (T) -> Void) {

    }

}

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

    private var streamingTask: Task<Void, Never>?

    private func stream() {
        logger.debug(#function)

        streamingTask = Task {
            do {
                for try await packet in WormholePacket.stream(from: input.bytes) {
                    guard !Task.isCancelled else { break }

                    handlePacket(packet)
                }
            } catch {
                logger.error("Serial read failure: \(error, privacy: .public)")

                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)

                guard !Task.isCancelled else { return }

                stream()
            }
        }
    }

    private func handlePacket(_ packet: WormholePacket) {

    }

}
