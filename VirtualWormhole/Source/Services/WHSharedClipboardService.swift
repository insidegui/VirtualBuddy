//
//  WHSharedClipboardService.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Cocoa
import OSLog

struct ClipboardData: Codable, Hashable {
    var type: NSPasteboard.PasteboardType.RawValue
    var value: Data
}

struct ClipboardMessage: Codable, Hashable {
    var timestamp: Date
    var data: [ClipboardData]
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

        Task {
            for try await message in connection.stream(for: ClipboardMessage.self) {
                handle(message.payload)
            }
        }

        startObservingClipboard()
    }

    private let pasteboard = NSPasteboard.general
    
    private func handle(_ message: ClipboardMessage) {
        guard !message.data.isEmpty, message.data != previousMessage?.data else { return }
        
        logger.debug("Handle clipboard message: \(String(describing: message))")
        
        previousMessage = message
        
        pasteboard.read(from: message.data)

        #if DEBUG
        logger.debug("⏱️ Clipboard message roundtrip time: \(String(format: "%.03f", Date.now.timeIntervalSince(message.timestamp)), privacy: .public)")
        #endif
    }
    
    private var clipboardTimer: Timer?
    
    private func startObservingClipboard() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { [weak self] _ in
            self?.updateIfNeeded()
        })
    }
    
    private func updateIfNeeded() {
        let currentData = ClipboardData.current
        guard currentData != previousMessage?.data else { return }

        #if DEBUG
        logger.debug("Clipboard contents changed: \(String(describing: currentData), privacy: .public)")
        #endif
        
        let message = ClipboardMessage(
            timestamp: .now,
            data: currentData
        )
        
        previousMessage = message
        
        Task {
            await connection.send(message, to: nil)
        }
    }

}

private extension ClipboardData {
    static let supportedTypes: [NSPasteboard.PasteboardType] = [
        .string,
        .rtf,
        .rtfd,
        .pdf,
        .png,
        .tiff,
    ]

    static var current: [ClipboardData] {
        return supportedTypes.compactMap { type in
            guard let data = NSPasteboard.general.data(forType: type) else {
                return nil
            }
            return ClipboardData(type: type.rawValue, value: data)
        }
    }
}

private extension NSPasteboard {
    func read(from data: [ClipboardData]) {
        clearContents()

        for item in data {
            setData(item.value, forType: PasteboardType(rawValue: item.type))
        }
    }
}
