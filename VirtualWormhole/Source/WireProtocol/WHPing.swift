//
//  WHPing.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 08/03/23.
//

import Foundation

struct WHPing: Codable {
    var date = Date.now
}

struct WHPong: Codable {
    var date = Date.now
}

extension WormholePacket {
    var isPing: Bool { payloadType == String(describing: WHPing.self) }
    var isPong: Bool { payloadType == String(describing: WHPong.self) }
}
