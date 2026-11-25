import AppKit
import SwiftUI
import VirtualUI
import VirtualWormhole

/// A dedicated window that VirtualBuddyGuest can show outside its menu bar panel.
enum GuestWindow: String, CaseIterable {
    case serviceTunnels
    #if ENABLE_USERDEFAULTS_SYNC
    case defaultsImport
    #endif

    var title: String {
        switch self {
        case .serviceTunnels: "Service Tunnels"
        #if ENABLE_USERDEFAULTS_SYNC
        case .defaultsImport: "Defaults Import"
        #endif
        }
    }
}

/// Manages the dedicated windows that VirtualBuddyGuest can show outside its menu bar panel.
///
/// VirtualBuddyGuest normally runs as an accessory app, but it switches to the regular activation policy
/// while at least one of these windows is open, so that it has a Dock icon and a main menu for as long as the user is working in them.
@MainActor
final class GuestWindowManager {
    private let hostSession: GuestHostSession

    init(hostSession: GuestHostSession) {
        self.hostSession = hostSession
    }

    private var windowControllers = [GuestWindow: NSWindowController]()

    var hasOpenWindows: Bool { !windowControllers.isEmpty }

    /// Shows the specified window, bringing it to the front if it's already open.
    func show(_ window: GuestWindow) {
        if let controller = windowControllers[window] {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let controller = HostingWindowController(
            id: "guest-\(window.rawValue)",
            rootView: content(for: window),
            requiresRegularActivationPolicy: true,
            onWindowClose: { [weak self] _ in
                self?.windowControllers[window] = nil
            }
        )
        controller.window?.title = window.title

        windowControllers[window] = controller

        controller.showWindow(nil)
    }

    @ViewBuilder
    private func content(for window: GuestWindow) -> some View {
        switch window {
        case .serviceTunnels:
            GuestTunnelsView(session: hostSession)
        #if ENABLE_USERDEFAULTS_SYNC
        case .defaultsImport:
            GuestDefaultsImportView(connection: hostSession)
        #endif
        }
    }
}
