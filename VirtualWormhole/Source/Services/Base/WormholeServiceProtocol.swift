//
//  WormholeServiceProtocol.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization

public protocol WormholeMultiplexer: AnyObject {

    var side: WHConnectionSide { get }
    
    func send<T: WHPayload>(_ payload: T, to peerID: WHPeerID?) async

    func stream<T: WHPayload>(for payloadType: T.Type) -> AsyncThrowingStream<(senderID: WHPeerID, payload: T), Error>
    
}

public protocol WormholeService: AnyObject {

    static var id: String { get }
    
    init(with connection: WormholeMultiplexer)
    
    func activate()
    
}
