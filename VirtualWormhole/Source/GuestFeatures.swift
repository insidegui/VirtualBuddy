import AppKit
import AVFoundation
import VMBridge

@MainActor
protocol GuestClipboard: AnyObject {
    var changeCount: Int { get }
    func read() -> [ClipboardItem]
    func write(_ items: [ClipboardItem])
}

@MainActor
final class SystemGuestClipboard: GuestClipboard {
    static let shared = SystemGuestClipboard()
    private let pasteboard = NSPasteboard.general
    var changeCount: Int { pasteboard.changeCount }
    func read() -> [ClipboardItem] {
        let types: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .pdf, .png, .tiff]
        return types.compactMap { type in
            if type == .tiff, pasteboard.types?.contains(.png) == true { return nil }
            return pasteboard.data(forType: type).map { ClipboardItem(type: type.rawValue, data: $0) }
        }
    }
    func write(_ items: [ClipboardItem]) {
        pasteboard.clearContents()
        for item in items { pasteboard.setData(item.data, forType: .init(item.type)) }
    }
}

@MainActor
final class HostClipboardCoordinator {
    static let shared = HostClipboardCoordinator(clipboard: SystemGuestClipboard.shared)
    let clipboard: any GuestClipboard
    private let relayEnabled: () -> Bool
    private var observers: [UUID: ([ClipboardItem]) -> Void] = [:]
    private var changeCount: Int
    private var items: [ClipboardItem]

    init(clipboard: any GuestClipboard, relayEnabled: @escaping () -> Bool = { !UserDefaults.standard.bool(forKey: "WHDisablePayloadPropagation") }) {
        self.clipboard = clipboard
        self.relayEnabled = relayEnabled
        changeCount = clipboard.changeCount
        items = clipboard.read()
    }

    func register(_ id: UUID, receive: @escaping ([ClipboardItem]) -> Void) {
        poll()
        observers[id] = receive
        receive(items)
    }

    func unregister(_ id: UUID) {
        observers[id] = nil
    }

    func poll() {
        guard changeCount != clipboard.changeCount else { return }
        changeCount = clipboard.changeCount
        let current = clipboard.read()
        guard current != items else { return }
        items = current
        for receive in observers.values { receive(current) }
    }

    func receive(_ current: [ClipboardItem], from id: UUID) {
        guard observers[id] != nil else { return }
        guard current != clipboard.read() else { return }
        clipboard.write(current)
        changeCount = clipboard.changeCount
        items = current
        guard relayEnabled() else { return }
        for (other, receive) in observers where other != id { receive(current) }
    }

}

@MainActor
struct GuestFeatureProviders {
    var clipboard: any GuestClipboard
    var notifications: (Set<String>, @escaping @MainActor (String) -> Void) throws -> (() -> Void)
    var desktopPicture: () async throws -> GuestDesktopPicture?
    var exportDefaults: (String, URL) async throws -> Void
    var importDefaults: (String, URL) async throws -> Void

    static var live: Self {
        Self(clipboard: SystemGuestClipboard.shared, notifications: { names, receive in
            var darwin: [SystemNotification] = []
            var distributed: [NSObjectProtocol] = []
            let center = DistributedNotificationCenter.default()
            do {
                for name in names {
                    let notification = SystemNotification(with: name) {
                        MainActor.assumeIsolated { receive(name) }
                    }
                    try notification.activate()
                    darwin.append(notification)
                    distributed.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                        MainActor.assumeIsolated { receive(name) }
                    })
                }
            } catch {
                darwin.forEach { $0.invalidate() }
                distributed.forEach { center.removeObserver($0) }
                throw error
            }
            return {
                darwin.forEach { $0.invalidate() }
                distributed.forEach { center.removeObserver($0) }
            }
        }, desktopPicture: {
            if let image = NSImage.desktopPicture,
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let picture = try await DesktopPictureEncoder.encode(cgImage) {
                return picture
            }
            // Modern wallpaper providers may not expose a Dock wallpaper window.
            guard let screen = NSScreen.main,
                  let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return try await DesktopPictureEncoder.encodeFile(at: url)
        }, exportDefaults: { id, url in
            guard let descriptor = DefaultsImportController().descriptors[id] else { throw GuestSessionError.unavailableDomain }
            try await descriptor.exportDefaults(to: url)
        }, importDefaults: { id, url in
            guard let descriptor = DefaultsImportController().descriptors[id] else { throw GuestSessionError.unavailableDomain }
            try await descriptor.importDefaults(from: url)
        })
    }
}

private enum DesktopPictureEncoder {
    static func encodeFile(at url: URL) async throws -> GuestDesktopPicture? {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return try await encode(image)
    }

    static func encode(_ image: CGImage) async throws -> GuestDesktopPicture? {
        try Task.checkCancellation()
        guard !image.isFullyTransparent() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, AVFileType.heic.rawValue as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.8,
            kCGImageDestinationImageMaxPixelSize: 512
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return GuestDesktopPicture(type: AVFileType.heic.rawValue, content: data as Data)
    }
}
