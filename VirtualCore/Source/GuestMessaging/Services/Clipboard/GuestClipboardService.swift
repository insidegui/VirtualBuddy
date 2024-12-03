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

        register(handleClipboard)

        DispatchQueue.main.async {
            self.activateObserver()
        }
    }

    @MainActor
    func activateObserver() {
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

public class GuestClipboardClient: GuestClipboardService, GuestServiceClient, @unchecked Sendable {
    override var isGuest: Bool { false }

    override func activateObserver() {
        /// In guest simulation mode, we simulate the guest sending content to the host,
        /// so the client (host) side disables clipboard observation and everything copied
        /// from the clipboard on the host is routed through the guest to the host client.
        #if DEBUG
        guard !UserDefaults.isGuestSimulationEnabled else {
            logger.notice("Skipping clipboard observation because guest simulation is enabled.")
            return
        }
        #endif

        super.activateObserver()
    }
}
