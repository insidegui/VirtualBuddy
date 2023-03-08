//
//  WormholeServiceProtocol.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization

protocol WormholeMultiplexer: AnyObject {
    
    func receive<T>(_ type: T.Type, using callback: @escaping (T) -> Void) where T: Codable
    func send<T>(_ payload: T, to peerID: WHPeerID?) where T: Codable
    
}

protocol WormholeService: AnyObject {

    static var id: String { get }
    
    init(with connection: WormholeMultiplexer)
    
    func activate()
    
}
