//
//  WHControlService.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 25/10/23.
//

import Foundation
import OSLog
import Combine

struct WHTestPayload: WHPayload {
    static let serviceType = WHControlService.self

    var date = Date.now
}

/// Service used for basic signaling between host and guest or vice-versa.
final class WHControlService: WormholeService {

    public static let port = WHServicePort.control

    static let id = "control"

    private lazy var logger = Logger(for: Self.self)

    var provider: WormholeConnectionProvider

    init(provider: WormholeConnectionProvider) {
        self.provider = provider
    }

    private lazy var cancellables = Set<AnyCancellable>()

    private var streamTask: Task<Void, Never>?

    private var sendTimer: Timer?

    func activate() {
        logger.debug(#function)

        streamTask = Task {
            do {
                for try await payload in provider.stream(for: WHTestPayload.self) {
                    logger.debug("Received test payload: \(String(describing: payload), privacy: .public)")
                }

                logger.debug("Test payload stream ended")
            } catch {
                logger.warning("Test payload stream interrupted: \(error, privacy: .public)")
            }
        }

        sendTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.logger.debug("Sending test payload")

            Task {
                await self.provider.broadcast(WHTestPayload())
            }
        }
    }
}
