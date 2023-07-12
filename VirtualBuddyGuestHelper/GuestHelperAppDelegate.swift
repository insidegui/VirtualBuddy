import Cocoa
import os.log

@main
final class GuestHelperAppDelegate: NSObject, NSApplicationDelegate {

    private let log = OSLog(subsystem: "codes.rambo.VirtualBuddyGuestHelper", category: String(describing: GuestHelperAppDelegate.self))

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.promptsUserIfNeeded = false

        NSWorkspace.shared.openApplication(
            at: Bundle.main.mainAppBundleURL,
            configuration: config) { _, error in
                if let error = error {
                    os_log("Failed to launch main app: %{public}@", log: self.log, type: .fault, String(describing: error))
                } else {
                    os_log("Main app launched successfully", log: self.log, type: .info)
                }

                DispatchQueue.main.async { NSApp?.terminate(nil) }
            }
    }

}

extension Bundle {

    var mainAppBundleURL: URL {
        bundleURL
            .deletingLastPathComponent() // VirtualBuddyGuestHelper.app
            .deletingLastPathComponent() // LoginItems
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents
    }

}
