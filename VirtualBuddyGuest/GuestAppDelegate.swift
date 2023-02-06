import Cocoa
import SwiftUI
import VirtualUI
import VirtualWormhole

@NSApplicationMain
final class GuestAppDelegate: NSObject, NSApplicationDelegate {

    private lazy var launchAtLoginManager = GuestLaunchAtLoginManager()

    private lazy var dashboardItem: StatusItemManager = {
        StatusItemManager(
            configuration: .default.id("dashboard"),
            statusItem: .button(label: { Image("StatusItem") }),
            content: GuestDashboard<WormholeManager>()
                .environmentObject(self.launchAtLoginManager)
                .environmentObject(WormholeManager.shared)
        )
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLoginManager.autoEnableIfNeeded()
        
        dashboardItem.install()
    }

}
