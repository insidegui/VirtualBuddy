import Cocoa
import SwiftUI
import VirtualUI
import VirtualWormhole
import OSLog

@NSApplicationMain
final class GuestAppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Guest", category: "GuestAppDelegate")

    private lazy var launchAtLoginManager = GuestLaunchAtLoginManager()

    private lazy var sharedFolders = GuestSharedFoldersManager()

    private lazy var dashboardItem: StatusItemManager = {
        StatusItemManager(
            configuration: .default.id("dashboard"),
            statusItem: .button(label: { Image("StatusItem") }),
            content: GuestDashboard()
                .environmentObject(self.launchAtLoginManager)
                .environmentObject(WormholeManager.sharedGuest)
                .environmentObject(self.sharedFolders)
        )
    }()

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

    private var isPoweringOff = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        /// Skip regular app activation if installation is needed (i.e. running from disk image).
        guard !installer.needsInstall else { return }

        launchAtLoginManager.autoEnableIfNeeded()

        WormholeManager.sharedGuest.activate()

        Task {
            try? await sharedFolders.mount()
        }
        
        dashboardItem.install()

        perform(#selector(showPanelForFirstLaunchIfNeeded), with: nil, afterDelay: 0.5)

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: nil) { _ in
            self.logger.notice("Received power off notification.")
            
            self.isPoweringOff = true
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()

        return true
    }

    @objc private func showPanelForFirstLaunchIfNeeded() {
        guard shouldShowPanelAfterLaunching else { return }
        shouldShowPanelAfterLaunching = false

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showPanelForFirstLaunchIfNeeded), object: nil)

        showPanel()
    }

    @objc private func showPanel() {
        dashboardItem.showPanel()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.debug(#function)

        guard isPoweringOff else { return .terminateNow }

        logger.notice("Guest is powering off, delaying slightly to allow for final messages to be sent to host.")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            logger.notice("Allowing guest to terminate now.")
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

}
