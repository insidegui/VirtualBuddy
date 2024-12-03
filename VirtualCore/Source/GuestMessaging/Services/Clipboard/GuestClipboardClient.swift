import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

public final class GuestClipboardClient: GuestClipboardService, GuestServiceClient, @unchecked Sendable {
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
