import Cocoa
import OSLog

final class GuestAppInstaller {

    private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Self.self))

    func installIfNeeded() throws {
        do {
            guard needsInstall else {
                logger.debug("Install not needed: running from supported path \(Bundle.main.bundleURL.deletingLastPathComponent().path, privacy: .public)")
                return
            }

            let destURL = URL(fileURLWithPath: "/Applications")
                .appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)

            logger.notice("Performing install (running from \(Bundle.main.bundleURL.deletingLastPathComponent().path, privacy: .public), installing to \(destURL.path, privacy: .public))")

            if FileManager.default.fileExists(atPath: destURL.path) {
                logger.debug("Removing existing app at \(destURL.path, privacy: .public)")

                if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).first {
                    logger.debug("Terminating existing app instance")

                    if !runningApp.forceTerminate() {
                        logger.error("Failed to terminate existing app instance")
                    }
                }

                try FileManager.default.removeItem(at: destURL)
            }

            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: destURL)

            try NSApplication.shared.relaunch(at: destURL.path)
        } catch {
            logger.error("Install failed: \(error, privacy: .public)")
            
            throw CocoaError(.coderInvalidValue, userInfo: [
                NSLocalizedDescriptionKey: "Failed to install the VirtualBuddyGuest app. This can occur if the Mac user account on the virtual machine can't write to /Applications.",
                NSUnderlyingErrorKey: error
            ])
        }
    }

    var needsInstall: Bool {
        guard !UserDefaults.standard.bool(forKey: "DisableInstall") else { return false }
        return !isRunningFromApplicationsDirectory
    }

    private var isRunningFromApplicationsDirectory: Bool {
        let directories = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .allDomainsMask, true)
        for directory in directories {
            if Bundle.main.bundlePath.hasPrefix(directory) { return true }
        }
        return false
    }

}

extension NSApplication {
    // Credit: Andy Kim (PFMoveApplication)
    func relaunch(at path: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier

        let xattrScript = "/usr/bin/xattr -d -r com.apple.quarantine \(path)"
        let script = "(while /bin/kill -0 \(pid) >&/dev/null; do /bin/sleep 0.1; done; \(xattrScript); /usr/bin/open \(path)) &"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [
            "-c",
            script
        ]

        try proc.run()

        exit(0)
    }
}
