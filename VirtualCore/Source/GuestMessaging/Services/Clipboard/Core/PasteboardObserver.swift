import Foundation
import AppKit

@MainActor
final class ClipboardObserver {
    typealias EventStream = AsyncStream<Int>
    let events: EventStream
    private let eventContinuation: EventStream.Continuation

    nonisolated init() {
        let (stream, continuation) = EventStream.makeStream()
        self.events = stream
        self.eventContinuation = continuation
    }

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                activate()
            } else {
                invalidate()
            }
        }
    }

    private var task: Task<Void, Error>?

    private func activate() {
        guard isEnabled else { return }

        task = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            var currentChangeCount = NSPasteboard.general.changeCount

            while true {
                try Task.checkCancellation()

                try await Task.sleep(for: .milliseconds(100))

                let newChangeCount = NSPasteboard.general.changeCount

                if newChangeCount != currentChangeCount {
                    currentChangeCount = newChangeCount

                    try Task.checkCancellation()

                    eventContinuation.yield(newChangeCount)
                }

                await Task.yield()
            }
        }
    }

    private func invalidate() {
        task?.cancel()
        task = nil
    }
}

// MARK: - Payload Encoding

extension VMClipboardData {
    static let supportedTypes: [NSPasteboard.PasteboardType] = [
        .string,
        .rtf,
        .rtfd,
        .pdf,
        .png,
        .tiff,
    ]

    static var current: [VMClipboardData] {
        guard let availableTypes = NSPasteboard.general.types else { return [] }

        return supportedTypes.compactMap { type in
            /// PNG and TIFF data are often present at the same time.
            /// Ignore TIFF data and preserve only the PNG data when that's the case,
            /// since TIFF data is usually much larger and unused.
            if type == .tiff {
                guard !availableTypes.contains(.png) else { return nil }
            }
            guard let data = NSPasteboard.general.data(forType: type) else {
                return nil
            }
            return VMClipboardData(type: type.rawValue, value: data)
        }
    }
}

extension NSPasteboard {
    func read(from data: [VMClipboardData]) {
        clearContents()

        for item in data {
            setData(item.value, forType: PasteboardType(rawValue: item.type))
        }
    }
}
