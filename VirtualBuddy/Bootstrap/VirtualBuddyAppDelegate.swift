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
    let library = VMLibraryController()
    let sessionManager = VirtualMachineSessionUIManager.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        DeepLinkHandler.bootstrap(library: library)

        NSApp?.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            try? await GuestAdditionsDiskImage.current.installIfNeeded()
        }

        #if DEBUG
        runLaunchDebugTasks()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let firstValidAssertion = sender.assertionsPreventingAppTermination.first {
            logger.debug("Preventing app termination due to active assertions: \(sender.assertionsPreventingAppTermination.map(\.reason).formatted(.list(type: .and)), privacy: .public)")

            let alert = NSAlert()
            alert.messageText = "Quit VirtualBuddy?"
            alert.informativeText = "VirtualBuddy is currently \(firstValidAssertion.reason). This will be cancelled if you quit the app."

            let button = alert.addButton(withTitle: "Quit")
            button.hasDestructiveAction = true

            let button2 = alert.addButton(withTitle: "Quit When Done")
            button2.keyEquivalent = "\r"

            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()

            switch response {
            case .alertFirstButtonReturn:
                logger.info("User decided to terminate now despite assertions :(")

                return .terminateNow
            case .alertSecondButtonReturn:
                logger.info("User wants app to terminate when assertions preventing termination are invalidated.")

                return .terminateLater
            default:
                logger.info("User cancelled termination request. Good.")
                
                return .terminateCancel
            }
        } else {
            return .terminateNow
        }
    }

}

extension NSWindow {
    /// At least as of macOS 14.4, a SwiftUI window's `identifier` matches the `id` that's set in SwiftUI.
    var isVirtualBuddyLibraryWindow: Bool { identifier?.rawValue == .vb_libraryWindowID }
}

#if DEBUG
// MARK: - Debugging Helpers

private extension VirtualBuddyAppDelegate {
    func runLaunchDebugTasks() {
        RunLoop.main.perform { [self] in
            MainActor.assumeIsolated {
                VirtualMachineSessionUIManager.shared.testImportVMIfEnabled(library: library)
            }
        }
    }
}
#endif
