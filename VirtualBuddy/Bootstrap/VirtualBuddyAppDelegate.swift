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
import Combine
import SwiftUI

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

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        GuestAdditionsDiskImage.default.$state.sink { state in
            switch state {
            case .ready:
                self.logger.debug("Default guest disk image ready")
            case .downloading:
                self.logger.debug("Default guest disk image downloading")
            case .installing:
                self.logger.debug("Default guest disk image installing")
            case .installFailed(let error):
                self.logger.debug("Default guest disk image installation failed - \(error, privacy: .public)")
            }
        }
        .store(in: &cancellables)

        Task {
            try? await GuestAdditionsDiskImage.default.installIfNeeded()
        }

        VBUSBDeviceRepository.shared.updateIfNeeded()

        #if DEBUG
        runLaunchDebugTasks()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Quitting is decided by one sequence that runs to completion before the app is told it can terminate:
    /// running virtual machines are saved (or shut down), then anything else that's preventing termination is dealt with.
    /// Termination is always answered exactly once, and a failure or cancellation leaves the app running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationTask == nil {
            terminationTask = Task { @MainActor [self] in
                await runTerminationSequence(for: sender)
            }
        }

        return .terminateLater
    }

    private var terminationTask: Task<Void, Never>?

    private func runTerminationSequence(for sender: NSApplication) async {
        guard await sessionManager.prepareForTermination() else {
            logger.info("Termination cancelled while stopping virtual machines")
            return cancelTermination(for: sender)
        }

        /// Virtual machines are handled above, which is why the assertion that's held for them doesn't count here.
        let otherAssertions = sender.assertionsPreventingAppTermination.filter { $0.id != VMLibraryController.runningMachinesAssertionID }

        guard let firstValidAssertion = otherAssertions.first else {
            return await finishTerminationAfterGuestTeardown()
        }

        logger.debug("Preventing app termination due to active assertions: \(otherAssertions.map(\.reason).formatted(.list(type: .and)), privacy: .public)")

        let reply: NSApplication.TerminateReply

        if let assertionReply = firstValidAssertion.handleShouldTerminate() {
            logger.debug("Assertion handles should terminate, returning its reply \(assertionReply)")

            reply = assertionReply
        } else {
            logger.debug("Assertion doesn't handle should terminate, performing default handling")

            let alert = NSAlert()
            alert.messageText = "Quit VirtualBuddy?"
            alert.informativeText = "VirtualBuddy is currently \(firstValidAssertion.reason). This will be cancelled if you quit the app."

            let button = alert.addButton(withTitle: "Quit")
            button.hasDestructiveAction = true

            let button2 = alert.addButton(withTitle: "Quit When Done")
            button2.keyEquivalent = "\r"

            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()

            reply = switch response {
            case .alertFirstButtonReturn: .terminateNow
            case .alertSecondButtonReturn: .terminateLater
            default: .terminateCancel
            }
        }

        switch reply {
        case .terminateCancel:
            logger.info("User cancelled termination request. Good.")
            cancelTermination(for: sender)
        case .terminateNow:
            logger.info("User decided to terminate now despite assertions :(")
            await finishTerminationAfterGuestTeardown()
        case .terminateLater:
            logger.info("User wants app to terminate when assertions preventing termination are invalidated.")

            /// Termination has already been deferred. The app terminates once the last assertion is invalidated.
            sender.shouldTerminateWhenLastAssertionInvalidated = true
        @unknown default:
            logger.fault("Unknown terminate reply \(reply, privacy: .public)")
            cancelTermination(for: sender)
        }
    }

    /// Answers the pending termination request with a cancellation and forgets everything about it,
    /// so that the next attempt to quit starts over.
    private func cancelTermination(for sender: NSApplication) {
        sender.shouldTerminateWhenLastAssertionInvalidated = false
        terminationTask = nil

        sender.reply(toApplicationShouldTerminate: false)
    }

    private func finishTerminationAfterGuestTeardown() async {
        await library.stopGuestCommunication()
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    private var settingsWindow: NSWindow?

    private(set) lazy var openSettingsAction = OpenVirtualBuddySettingsAction { [weak self] in
        self?.openSettingsWindow()
    }

    private func openSettingsWindow() {
        if let settingsWindow {
            logger.debug("Settings window already available, showing")
            settingsWindow.makeKeyAndOrderFront(self)
            return
        }

        let rootView = SettingsScreen(
            enableAutomaticUpdates: updateController.automaticUpdatesBinding,
            deepLinkSentinel: DeepLinkHandler.shared.sentinel
        )
        .environmentObject(settingsContainer)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsScreen.width, height: SettingsScreen.minHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)

        window.makeKeyAndOrderFront(self)
        window.center()

        self.settingsWindow = window
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
