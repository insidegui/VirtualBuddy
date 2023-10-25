//
//  WHDarwinNotificationsService.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 08/03/23.
//

import Cocoa
import OSLog
import Combine

enum DarwinNotificationMessage: WHPayload {
    static let resendOnReconnect = true
    
    case post(String)
    case subscribe(String)
}

final class WHDarwinNotificationsService: WormholeService {

    static let id = "darwinNotifications"

    private lazy var logger = Logger(for: Self.self)

    private let peerPostedNotificationSubject = PassthroughSubject<(name: String, peerID: WHPeerID), Never>()

    var onPeerNotificationReceived: AnyPublisher<(name: String, peerID: WHPeerID), Never> {
        peerPostedNotificationSubject.eraseToAnyPublisher()
    }

    var connection: WormholeMultiplexer

    init(with connection: WormholeMultiplexer) {
        self.connection = connection
    }

    func activate() {
        logger.debug(#function)

        Task {
            for try await message in connection.stream(for: DarwinNotificationMessage.self) {
                handle(message.payload, from: message.senderID)
            }
        }
    }

    private func handle(_ message: DarwinNotificationMessage, from peerID: WHPeerID) {
        logger.debug("Handle message: \(String(describing: message))")

        switch message {
        case .post(let name):
            peerPostedNotificationSubject.send((name, peerID))
        case .subscribe(let name):
            createSubscription(for: name, peerID: peerID)
        }
    }

    private var subscriptions = [SystemNotification]()

    private func createSubscription(for name: String, peerID: WHPeerID) {
        do {
            let note = SystemNotification(with: name) { [weak self] in
                guard let self = self else { return }
                self.sendPostMessage(with: name, to: peerID)
            }
            subscriptions.append(note)

            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: nil) { [weak self] _ in
                guard let self = self else { return }
                self.sendPostMessage(with: name, to: peerID)
            }

            try note.activate()
        } catch {
            logger.error("Error creating notification subscription for \"\(name)\": \(error, privacy: .public)")
        }
    }

    private func sendPostMessage(with name: String, to peerID: WHPeerID) {
        #if DEBUG
        logger.debug("Posting \(name, privacy: .public) to \(peerID, privacy: .public)")
        #endif

        Task {
            await connection.send(DarwinNotificationMessage.post(name), to: peerID)
        }
    }

}
