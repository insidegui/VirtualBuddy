import Cocoa
import SwiftUI
import VirtualUI
import VirtualCore
import OSLog

let kGuestAppSubsystem = "codes.rambo.VirtualBuddyGuest"

final class GuestAppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: kGuestAppSubsystem, category: "GuestAppDelegate")

    private lazy var launchAtLoginManager = GuestLaunchAtLoginManager()

    private lazy var sharedFolders = GuestSharedFoldersManager()

    private lazy var dashboardItem: StatusItemManager = {
        StatusItemManager(
            configuration: .default.id("dashboard"),
            statusItem: .button(label: { Image("StatusItem") }),
            content: GuestDashboard<GuestAppServices>()
                .environmentObject(self.launchAtLoginManager)
                .environmentObject(self.sharedFolders)
                .environmentObject(GuestAppServices.shared)
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

            GuestAppServices.shared.activate()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        UserDefaults.standard.set(true, forKey: kVerboseLoggingFlag)
        #endif

        /// Skip regular app activation if installation is needed (i.e. running from disk image).
        guard !installer.needsInstall else { return }

        launchAtLoginManager.autoEnableIfNeeded()

        Task {
            try? await sharedFolders.mount()
        }
        
        dashboardItem.install()

        perform(#selector(showPanelForFirstLaunchIfNeeded), with: nil, afterDelay: 0.5)
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

}
