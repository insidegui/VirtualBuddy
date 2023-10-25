//
//  WHPing.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 08/03/23.
//

import Foundation

struct WHPing: WHPayload {
    var date = Date.now

    static let serviceType = WHControlService.self
}

struct WHPong: WHPayload {
    var date = Date.now

    static let serviceType = WHControlService.self
}

extension WormholePacket {
    var isPing: Bool { payloadType == String(describing: WHPing.self) }
    var isPong: Bool { payloadType == String(describing: WHPong.self) }
}

extension WormholePacket {
    static var ping: WormholePacket {
        get throws { try WormholePacket(WHPing()) }
    }
    static var pong: WormholePacket {
        get throws { try WormholePacket(WHPong()) }
    }
}
