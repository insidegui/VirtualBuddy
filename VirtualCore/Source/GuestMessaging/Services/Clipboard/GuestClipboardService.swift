import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

let kGuestClipboardServiceID = "codes.rambo.VirtualBuddy.ClipboardService"

public class GuestClipboardService: GuestService, @unchecked Sendable {
    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "GuestClipboardService")

    public override var id: String { kGuestClipboardServiceID }

    var isGuest: Bool { true }

    private let observer = ClipboardObserver()

    private var observerTask: Task<Void, Never>?

    public override func bootstrapCompleted() {
        logger.debug(#function)

        register(handleClipboard)

        DispatchQueue.main.async {
            self.activateObserver()
        }
    }

    @MainActor
    private func activateObserver() {
        let events = observer.events
        observerTask = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { break }

                await self?.clipboardChanged()
            }
        }

        observer.isEnabled = true
    }

    private func clipboardChanged() async {
        do {
            let reference = await latestPayload?.data
            let data = VMClipboardData.current
            guard data != reference else { return }

            let payload = VMClipboardPayload(timestamp: .now, data: data)

            logger.debug("Sending clipboard: \(payload)")

            await updateCurrentPayload(payload)

            try await send(payload)
        } catch {
            logger.error("Clipboard submission failed. \(error, privacy: .public)")
        }
    }

    private let pasteboard = NSPasteboard.general

    @MainActor
    private var latestPayload: VMClipboardPayload?

    @Sendable private func handleClipboard(_ payload: VMClipboardPayload, peer: VMPeerConnection) async throws {
        let reference = await latestPayload?.data
        guard payload.data != reference else { return }

        logger.debug("Received clipboard: \(String(describing: payload))")

        await read(payload)

        logger.debug("Finished reading clipboard payload into pasteboard")
    }

    private func read(_ payload: VMClipboardPayload) async {
        pasteboard.read(from: payload.data)

        await updateCurrentPayload(payload)
    }

    private func updateCurrentPayload(_ payload: VMClipboardPayload) async {
        await MainActor.run { [weak self] in
            self?.latestPayload = payload
        }
    }
}

public class GuestClipboardClient: GuestClipboardService, @unchecked Sendable {
    override var isGuest: Bool { false }
}
