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

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLoginManager.autoEnableIfNeeded()

        Task {
            try? await sharedFolders.mount()
        }
        
        dashboardItem.install()
    }

}
