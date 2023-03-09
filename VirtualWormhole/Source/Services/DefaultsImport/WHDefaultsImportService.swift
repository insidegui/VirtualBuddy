//
//  WHDefaultsImportService.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 09/03/23.
//

import Cocoa
import OSLog
import Combine

enum DefaultsImportMessage: Codable {
    case exportDomain(String)
    case domainExported(String)
}

final class WHDefaultsImportService: WormholeService {

    static let id = "defaultsImport"

    private lazy var logger = Logger(for: Self.self)

    var connection: WormholeMultiplexer

    init(with connection: WormholeMultiplexer) {
        self.connection = connection
    }

    func activate() {
        logger.debug(#function)

        Task {
            for try await message in connection.stream(for: DefaultsImportMessage.self) {
                handle(message.payload, from: message.senderID)
            }
        }
    }

    private func handle(_ message: DefaultsImportMessage, from peerID: WHPeerID) {
        logger.debug("Handle message: \(String(describing: message))")

        #warning("TODO: Implement")
    }

}
