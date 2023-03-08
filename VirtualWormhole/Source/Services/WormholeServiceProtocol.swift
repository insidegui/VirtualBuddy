//
//  WormholeServiceProtocol.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization

protocol WormholeMultiplexer: AnyObject {
    
    func send<T: Codable>(_ payload: T, to peerID: WHPeerID?) async

    func stream<T: Codable>(for payloadType: T.Type) -> AsyncThrowingStream<(senderID: WHPeerID, payload: T), Error>
    
}

protocol WormholeService: AnyObject {

    static var id: String { get }
    
    init(with connection: WormholeMultiplexer)
    
    func activate()
    
}
