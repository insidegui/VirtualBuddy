//
//  WHDesktopPictureService.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 18/06/25.
//

import Cocoa
import OSLog
import AVFoundation
import Combine

public struct DesktopPictureMessage: WHPayload {
    public internal(set) var type: String
    public internal(set) var content: Data

    public static let resendOnReconnect = true
}

final class WHDesktopPictureService: WormholeService {

    static let id = "desktopPicture"

    private lazy var logger = Logger(for: Self.self)

    var connection: WormholeMultiplexer

    init(with connection: WormholeMultiplexer) {
        self.connection = connection
    }

    static let imageProperties = [
        kCGImageDestinationLossyCompressionQuality: 0.8,
        kCGImageDestinationImageMaxPixelSize: 512
    ] as CFDictionary

    private let peerSentDesktopPictureSubject = PassthroughSubject<(message: DesktopPictureMessage, peerID: WHPeerID), Never>()

    var onPeerPeerDesktopPictureReceived: AnyPublisher<(message: DesktopPictureMessage, peerID: WHPeerID), Never> {
        peerSentDesktopPictureSubject.eraseToAnyPublisher()
    }

    func activate() {
        logger.debug(#function)

        Task {
            for try await message in connection.stream(for: DesktopPictureMessage.self) {
                logger.debug("Received desktop picture message with \(message.payload.content.count) bytes of image data.")

                peerSentDesktopPictureSubject.send((message.payload, message.senderID))
            }
        }

        guard connection.side == .guest else { return }

        Task {
            try? await Task.sleep(for: .seconds(2))

            guard let image = NSImage.desktopPicture else {
                logger.error("Error getting desktop picture for main screen.")
                return
            }

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                logger.error("Error getting CGImage from desktop picture.")
                return
            }

            guard let cfData = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
                logger.error("Failed to create CFMutableData")
                return
            }
            guard let destination = CGImageDestinationCreateWithData(cfData, AVFileType.heic.rawValue as CFString, 1, nil) else {
                logger.error("Failed to create CGImageDestination")
                return
            }

            CGImageDestinationAddImage(destination, cgImage, Self.imageProperties)
            CGImageDestinationFinalize(destination)

            let payload = DesktopPictureMessage(type: AVFileType.heic.rawValue, content: cfData as Data)

            logger.info("Sending payload with \(payload.content.count) bytes")

            await connection.send(payload, to: nil)
        }
    }

}
