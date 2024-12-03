import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

let kGuestClipboardServiceID = "codes.rambo.VirtualBuddy.ClipboardService"

public class GuestClipboardService: GuestService, @unchecked Sendable {
    let logger = Logger(subsystem: kVirtualMessagingSubsystem, category: "GuestClipboardService")

    public override var id: String { kGuestClipboardServiceID }

    var isGuest: Bool { true }

    let observer = ClipboardObserver()

    private var observerTask: Task<Void, Never>?

    public override func bootstrapCompleted() {
        logger.debug(#function)

        register { [weak self] in
            try await self?.handleClipboard($0, peer: $1)
        }
    }

    public override func connected(_ connection: VMPeerConnection) {
        super.connected(connection)

        DispatchQueue.main.async {
            self.activateObserver()
        }
    }

    public override func disconnected(_ connection: VMPeerConnection) {
        super.disconnected(connection)

        DispatchQueue.main.async {
            self.invalidateObserver()
        }
    }

    @MainActor
    func activateObserver() {
        logger.debug(#function)

        let events = observer.events
        observerTask = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { break }

                await self?.clipboardChanged()
            }
        }

        observer.isEnabled = true
    }

    @MainActor
    func invalidateObserver() {
        logger.debug(#function)

        observer.isEnabled = false
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
