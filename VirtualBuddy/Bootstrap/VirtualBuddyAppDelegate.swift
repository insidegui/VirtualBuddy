//
//  VirtualBuddyNSApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import Cocoa
@_exported import VirtualCore
@_exported import VirtualUI
import VirtualWormhole
import DeepLinkSecurity
import OSLog

#if BUILDING_NON_MANAGED_RELEASE
#error("Trying to build for release without using the managed scheme. This build won't include managed entitlements. This error is here for Rambo, you may safely comment it out and keep going.")
#endif

@MainActor
@objc final class VirtualBuddyAppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(for: VirtualBuddyAppDelegate.self)

    let settingsContainer = VBSettingsContainer.current
    let updateController = SoftwareUpdateController.shared
    let library = VMLibraryController.shared
    let sessionManager = VirtualMachineSessionUIManager.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        DeepLinkHandler.bootstrap(updatingWindows: self.updatingWindows(perform:))

        NSApp?.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            try? await GuestAdditionsDiskImage.current.installIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func restoreDefaultWindowPosition(_ sender: Any?) {
        guard let window = NSApp?.keyWindow ?? NSApp?.mainWindow else { return }
        
        window.setFrame(.init(x: 0, y: 0, width: 960, height: 600), display: true, animate: false)
        window.center()
    }

    /// `true` if the VirtualBuddy library window was previously closed, but got re-opened due to the app being reactivated.
    /// 
    /// This is used to close the library window when opening a file or URL in VirtualBuddy, as we don't want the library window
    /// to show up whenever a file or URL is opened in the app, it should only show up on launch or when the app is re-opened
    /// due to other interactions such as clicking the icon in the Dock when there are no other windows visible.
    private var appReopenCausedLibraryWindowOpen = false

    func application(_ application: NSApplication, open urls: [URL]) {
        updatingWindows {
            for url in urls {
                sessionManager.open(fileURL: url, library: library)
            }
        }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        let visibleWindowCount = NSApplication.shared.windows.filter(\.isVisible).count

        let libraryWindowOpen = isLibraryWindowOpen

        /// If the library window is not currently visible, then its visibility state after leaving this method will be the result of the app being re-opened.
        appReopenCausedLibraryWindowOpen = !libraryWindowOpen

        logger.debug("willBecomeActive (visibleWindowCount = \(visibleWindowCount, privacy: .public), isLibraryWindowOpen = \(libraryWindowOpen, privacy: .public), appReopenCausedLibraryWindowOpen = \(self.appReopenCausedLibraryWindowOpen, privacy: .public))")
    }

    /// Performs a block that may or may not update the list of visible windows, preventing the main library window from being re-opened in case it's not needed.
    /// This is used when handling the opening of files/links so that the library window is not brought to the foreground unnecessarily.
    private func updatingWindows(perform block: () -> Void) {
        let visibleWindowCountBeforeUpdates = NSApplication.shared.windows.filter(\.isVisible).count

        block()

        let visibleWindowCountAfterUpdates = NSApplication.shared.windows.filter(\.isVisible).count

        logger.debug("Visible windows before updates: \(visibleWindowCountBeforeUpdates, privacy: .public), after updates: \(visibleWindowCountAfterUpdates, privacy: .public)")

        /// If the update has opened new windows and the library window is visible, then close the library window as it was only shown as a side-effect of performing the updates.
        if appReopenCausedLibraryWindowOpen, let libraryWindow {
            logger.debug("Closing library window because it was automatically opened by SwiftUI due to a URL open")

            libraryWindow.close()

            appReopenCausedLibraryWindowOpen = false
        }
    }

    private var isLibraryWindowOpen: Bool {
        NSApplication.shared.windows.contains(where: { $0.isVirtualBuddyLibraryWindow && $0.isVisible })
    }

    private var libraryWindow: NSWindow? { NSApplication.shared.windows.first(where: { $0.isVirtualBuddyLibraryWindow }) }

}

extension NSWindow {
    /// At least as of macOS 14.4, a SwiftUI window's `identifier` matches the `id` that's set in SwiftUI.
    var isVirtualBuddyLibraryWindow: Bool { identifier?.rawValue == .vb_libraryWindowID }
}
