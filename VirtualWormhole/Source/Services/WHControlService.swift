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

        Timer
            .publish(every: VirtualWormholeConstants.pingIntervalInSeconds, tolerance: VirtualWormholeConstants.pingIntervalInSeconds * 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }

                Task {
                    await self.connection.send(WHPing(), to: nil)
                }
            }
            .store(in: &cancellables)
    }

}
