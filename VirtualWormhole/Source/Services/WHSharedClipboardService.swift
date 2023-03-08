//
//  WHSharedClipboardService.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import Virtualization
import OSLog

struct ClipboardMessage: Codable {
    let timestamp: Int
    let stringValue: String?
}

final class WHSharedClipboardService: WormholeService {

    static let id = "clipboard"
    
    private lazy var logger = Logger(for: Self.self)

    var connection: WormholeMultiplexer

    init(with connection: WormholeMultiplexer) {
        self.connection = connection
    }
    
    private var previousMessage: ClipboardMessage?
    
    func activate() {
        logger.debug(#function)

        connection.receive(ClipboardMessage.self) { [weak self] in
            self?.handle($0)
        }
        
        startObservingClipboard()
    }
    
    private func handle(_ message: ClipboardMessage) {
        guard let str = message.stringValue, str != previousMessage?.stringValue else { return }
        
        logger.debug("Handle clipboard message: \(String(describing: message))")
        
        previousMessage = message
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
    }
    
    private var clipboardTimer: Timer?
    
    private func startObservingClipboard() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { [weak self] _ in
            self?.updateIfNeeded()
        })
    }
    
    private func updateIfNeeded() {
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        guard str != previousMessage?.stringValue else { return }
        
        logger.debug("Clipboard contents changed")
        
        let message = ClipboardMessage(
            timestamp: Int(Date().timeIntervalSinceReferenceDate),
            stringValue: str
        )
        
        previousMessage = message
        
        connection.send(message, to: nil)
    }

}
