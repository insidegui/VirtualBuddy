//
//  WormholeManager.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization
import OSLog
import MultipeerKit

public final class WormholeManager: NSObject {
    
    public enum Side: Int, CustomStringConvertible {
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
    
    weak var vm: VZVirtualMachine!

    let serviceTypes: [WormholeService.Type] = [
        WHSharedClipboardService.self
    ]
    
    var activeServices: [WormholeService] = []
    
    let side: Side
    
    public init(for side: Side) {
        self.side = side

        super.init()

        for serviceType in serviceTypes {
            logger.debug("Registered \(String(describing: serviceType), privacy: .public)")
            
            let service = serviceType.init(with: transceiver)
            
            service.activate()
            
            activeServices.append(service)
        }
        
        logger.debug("Initialized for \(side, privacy: .public)")
        
        startTransceiver()
    }
    
    deinit {
        transceiver.stop()
    }
    
    private var connectedPeer: Peer?
    
    private lazy var transceiver = MultipeerTransceiver(
        configuration: MultipeerConfiguration(
            serviceType: "whsv",
            peerName: "Host",
            defaults: .standard,
            security: .init(identity: nil, encryptionPreference: .required, invitationHandler: { [weak self] in
                self?.handlePeerInvitation(from: $0, with: $1, decision: $2)
            }),
            invitation: .automatic
        )
    )
    
}

// MARK: - Multipeer Integration

extension MultipeerTransceiver: WormholeMultiplexer {
    
    func receive<T>(_ type: T.Type, using callback: @escaping (T) -> Void) where T : Decodable, T : Encodable {
        receive(type) { payload, _ in
            callback(payload)
        }
    }
    
    func send<T>(_ payload: T) where T : Decodable, T : Encodable {
        broadcast(payload)
    }
    
}

private extension WormholeManager {
    
    func handlePeerInvitation(from peer: Peer, with data: Data?, decision: @escaping (Bool) -> Void) {
        guard peer.id == connectedPeer?.id || connectedPeer == nil else {
            logger.debug("Refusing invitation from \(peer.name): not our buddy")
            decision(false)
            return
        }
        
        decision(true)
    }
    
    func startTransceiver() {
        transceiver.peerConnected = { [weak self] peer in
            guard let self = self else { return }
            
            guard self.connectedPeer == nil else {
                self.logger.error("Refusing connection from \(peer.name) because we already have a remote peer")
                return
            }
            
            self.logger.debug("Connected: \(peer.name)")
            
            self.connectedPeer = peer
        }
        
        transceiver.peerDisconnected = { [weak self] peer in
            guard let self = self else { return }
            
            guard peer.id == self.connectedPeer?.id else {
                self.logger.error("Ignoring disconnect from \(peer.name), which is not our buddy")
                return
            }
            
            self.logger.debug("Disconnected: \(peer.name)")
            
            self.connectedPeer = nil
        }
        
        transceiver.resume()
    }
    
}
