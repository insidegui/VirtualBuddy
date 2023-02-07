import Cocoa
import SwiftUI
import VirtualUI
import VirtualWormhole

@NSApplicationMain
final class GuestAppDelegate: NSObject, NSApplicationDelegate {

    private lazy var launchAtLoginManager = GuestLaunchAtLoginManager()

    private lazy var sharedFolders = GuestSharedFoldersManager()

    private lazy var dashboardItem: StatusItemManager = {
        StatusItemManager(
            configuration: .default.id("dashboard"),
            statusItem: .button(label: { Image("StatusItem") }),
            content: GuestDashboard<WormholeManager>()
                .environmentObject(self.launchAtLoginManager)
                .environmentObject(WormholeManager.shared)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        /// Skip regular app activation if installation is needed (i.e. running from disk image).
        guard !installer.needsInstall else { return }

        launchAtLoginManager.autoEnableIfNeeded()

        WormholeManager.shared.activate()

        Task {
            try? await sharedFolders.mount()
        }
        
        dashboardItem.install()

        perform(#selector(showPanelForFirstLaunchIfNeeded), with: nil, afterDelay: 0.5)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardItem.showPanel()

        return true
    }

    @objc private func showPanelForFirstLaunchIfNeeded() {
        guard shouldShowPanelAfterLaunching else { return }
        shouldShowPanelAfterLaunching = false

        dashboardItem.showPanel()
    }

}
