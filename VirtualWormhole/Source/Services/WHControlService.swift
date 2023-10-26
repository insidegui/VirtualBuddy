//
//  WHControlService.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 25/10/23.
//

import Foundation
import OSLog
import Combine

/// Service used for basic signaling between host and guest or vice-versa.
final class WHControlService: WormholeService {

    public static let port = WHServicePort.control

    static let id = "control"

    private lazy var logger = Logger(for: Self.self)

    var connection: WormholeMultiplexer

    init(with connection: WormholeMultiplexer) {
        self.connection = connection
    }

    private lazy var cancellables = Set<AnyCancellable>()

    func activate() {
        logger.debug(#function)
    }

}
