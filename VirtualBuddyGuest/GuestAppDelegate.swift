import Cocoa
import SwiftUI
import VirtualUI
import VirtualCore
import OSLog

@NSApplicationMain
final class GuestAppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "codes.rambo.VirtualBuddyGuest", category: "GuestAppDelegate")

    private let testServer = VirtualMessagingChannel(type: .server, address: .vsock(cid: nil, port: 1024))

    private lazy var launchAtLoginManager = GuestLaunchAtLoginManager()

    private lazy var sharedFolders = GuestSharedFoldersManager()

    private lazy var dashboardItem: StatusItemManager = {
        StatusItemManager(
            configuration: .default.id("dashboard"),
            statusItem: .button(label: { Image("StatusItem") }),
            content: GuestDashboard<VirtualMessagingChannel>()
                .environmentObject(self.launchAtLoginManager)
                .environmentObject(self.testServer)
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
        #if DEBUG
        UserDefaults.standard.set(true, forKey: kVerboseLoggingFlag)
        #endif

        /// Skip regular app activation if installation is needed (i.e. running from disk image).
        guard !installer.needsInstall else { return }

        launchAtLoginManager.autoEnableIfNeeded()

        Task {
            do {
                try await testServer.activate()

                logger.notice("Test server activated")

                for await message in testServer.messages {
                    logger.notice("Server received: \(message, privacy: .public)")
                }
            } catch {
                logger.error("Test server activation failed. \(error, privacy: .public)")
            }
        }

        Task {
            while true {
                try await Task.sleep(for: .seconds(3))

                logger.info("Sending test message...")

                try await testServer.broadcast(TestVMPayload())

                await Task.yield()
            }
        }

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
