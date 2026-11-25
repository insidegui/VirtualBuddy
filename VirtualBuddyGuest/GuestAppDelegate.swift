import Cocoa
import SwiftUI
import VirtualUI
import VirtualWormhole
import OSLog

@NSApplicationMain
@MainActor
final class GuestAppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Guest", category: "GuestAppDelegate")

    private lazy var launchAtLoginManager = GuestLaunchAtLoginManager()

    private let hostConnection = GuestHostSession()
    private var connectionTask: Task<Void, Never>?

    deinit { connectionTask?.cancel() }

    private lazy var sharedFolders = GuestSharedFoldersManager()

    private lazy var windowManager = GuestWindowManager(hostSession: hostConnection)

    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        item.behavior = .removalAllowed
        item.button?.image = NSImage(named: "StatusItem")
        item.button?.setAccessibilityLabel("VirtualBuddy Guest")

        return item
    }()

    private lazy var statusItemController = StatusItemController(statusItem: statusItem, delegate: self)

    /// The controller for the menu bar panel, only available while the panel is being presented.
    private var panelController: StatusBarMenuWindowController?

    private func makePanelController() -> StatusBarMenuWindowController {
        let actions = GuestDashboardActions(
            showWindow: { [weak self] in self?.showWindow($0) },
            dismiss: { [weak self] in self?.hidePanel() }
        )

        let controller = StatusBarMenuWindowController(
            statusItem: statusItem,
            rootView: GuestDashboard()
                .environment(launchAtLoginManager)
                .environment(hostConnection)
                .environment(sharedFolders)
                .environment(\.guestDashboardActions, actions)
        )

        controller.windowWillClose = { [weak self] closingController in
            guard let self, closingController === panelController else { return }
            panelController = nil
        }

        return controller
    }

    private var shouldShowPanelAfterLaunching: Bool {
        get { !UserDefaults.standard.bool(forKey: "shownPanelOnFirstLauch") || UserDefaults.standard.bool(forKey: "ShowPanelOnLaunch") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "shownPanelOnFirstLauch")
            UserDefaults.standard.synchronize()
        }
    }

    private let installer = GuestAppInstaller()

    func applicationWillFinishLaunching(_ notification: Notification) {
        do {
            try installer.installIfNeeded()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        /// Skip regular app activation if installation is needed (i.e. running from disk image).
        guard !installer.needsInstall else { return }

        launchAtLoginManager.autoEnableIfNeeded()

        connectionTask = hostConnection.start()

        Task {
            try? await sharedFolders.mount()
        }
        
        statusItemController.configure()

        perform(#selector(showPanelForFirstLaunchIfNeeded), with: nil, afterDelay: 0.5)

    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        /// Let AppKit bring back the app's windows when it's reopened while it has a Dock icon.
        guard !windowManager.hasOpenWindows else { return true }

        /// Reopening the app is the only way to get the status item back after the user has removed it from the menu bar.
        statusItem.isVisible = true

        showPanel()

        return true
    }

    @objc private func showPanelForFirstLaunchIfNeeded() {
        guard shouldShowPanelAfterLaunching else { return }
        shouldShowPanelAfterLaunching = false

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showPanelForFirstLaunchIfNeeded), object: nil)

        showPanel()
    }

    private func showPanel() {
        statusItemController.showPanel()
    }

    private func hidePanel() {
        statusItemController.hidePanel()
    }

    private func showWindow(_ window: GuestWindow) {
        hidePanel()

        windowManager.show(window)
    }

    private var startedFinalSendBeforeTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.debug(#function)

        guard !startedFinalSendBeforeTermination else { return .terminateLater }
        startedFinalSendBeforeTermination = true

        /// The wait for the host connection below gives the system enough time to process the unlock.
        panelController?.unlockMenuBar()

        Task {
            await hostConnection.prepareForTermination()

            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

}

// MARK: - StatusItemControllerDelegate

extension GuestAppDelegate: StatusItemControllerDelegate {
    func statusItemControllerPanelWindow(_ controller: StatusItemController) -> NSWindow? {
        panelController?.window
    }

    func statusItemControllerWillShowPanel(_ controller: StatusItemController) {
        launchAtLoginManager.refresh()
    }

    func statusItemControllerDidRequestShowPanel(_ controller: StatusItemController) {
        let panelController = panelController ?? makePanelController()
        self.panelController = panelController

        panelController.showWindow(self)
    }

    func statusItemControllerDidRequestHidePanel(_ controller: StatusItemController, animated: Bool) {
        panelController?.close(animated: animated)
    }
}
