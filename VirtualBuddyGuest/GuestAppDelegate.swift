import Cocoa
import SwiftUI
import VirtualUI

@NSApplicationMain
final class GuestAppDelegate: NSObject, NSApplicationDelegate {

    private lazy var dashboardItem: StatusItemManager = {
        StatusItemManager(
            configuration: .default.id("dashboard"),
            statusItem: .button(label: { Image("StatusItem") }),
            content: GuestDashboard()
        )
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dashboardItem.install()
    }

}
