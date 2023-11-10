//
//  WHTypes.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 28/10/23.
//

import Foundation

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
