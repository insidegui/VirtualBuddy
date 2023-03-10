//
//  WormholeServiceClient.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 10/03/23.
//

import Foundation

public protocol WormholeServiceClient {
    associatedtype ServiceType: WormholeService

    init(with service: ServiceType)
}
