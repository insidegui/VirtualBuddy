import Cocoa
import OSLog

final class GuestAppInstaller {

    private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Self.self))

    func installIfNeeded() throws {
        do {
            let needsUpdate = mountedGuestImageNeedsInstall

            guard !needsUpdate else {
                logger.notice("🚀 Relaunching from mounted image for update")
                try NSApplication.shared.relaunch(at: mountedImageAppURL.path)
                return
            }

            guard needsInstall else {
                logger.debug("Install not needed: running from supported path and updated not needed. Path: \(Bundle.main.bundleURL.deletingLastPathComponent().path, privacy: .public)")
                return
            }

            let destURL = URL(fileURLWithPath: "/Applications")
                .appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)

            logger.notice("Performing install (running from \(Bundle.main.bundleURL.deletingLastPathComponent().path, privacy: .public), installing to \(destURL.path, privacy: .public))")

            if FileManager.default.fileExists(atPath: destURL.path) {
                logger.debug("Removing existing app at \(destURL.path, privacy: .public)")

                if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).first(where: { $0.bundleURL == destURL }) {
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

    static var installEnabled: Bool { !UserDefaults.standard.bool(forKey: "DisableInstall") }
    
    var needsInstall: Bool {
        guard Self.installEnabled else { return false }
        return !isRunningFromApplicationsDirectory
    }

    private var isRunningFromApplicationsDirectory: Bool {
        let directories = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .allDomainsMask, true)
        for directory in directories {
            if Bundle.main.bundlePath.hasPrefix(directory) { return true }
        }
        return false
    }

    private var mountedImageAppURL: URL { URL(fileURLWithPath: "/Volumes/Guest/VirtualBuddyGuest.app") }

    /// `true` if there's a VirtualBuddyGuest image mounted at `/Volumes/Guest`
    /// for which the following conditions are true:
    /// 1 - The guest in the volume has a different `VBGuestBuildID` from this process
    /// 2 - The guest in the volume has a `CFBundleVersion` that's **greater than or equal to** the `CFBundleVersion` of this process
    private var mountedGuestImageNeedsInstall: Bool {
        guard Self.installEnabled else { return false }
        
        guard FileManager.default.fileExists(atPath: "/Volumes/Guest") else { return false }

        logger.debug("Guest volume is mounted, checking app version")

        let imageURL = mountedImageAppURL

        guard imageURL.path != Bundle.main.bundleURL.path else {
            logger.debug("We're the mounted image app, skipping update checks.")
            return false
        }

        guard let imageBundle = Bundle(url: imageURL) else {
            logger.error("Couldn't get bundle at \(imageURL.path, privacy: .public)")
            return false
        }

        guard let imageBuildID = imageBundle.vbGuestBuildID else {
            logger.error("Couldn't find VBGuestBuildID in image bundle")
            return false
        }

        guard let imageBundleVersion = imageBundle.bundleVersion else {
            logger.error("Couldn't find CFBundleVersion in image bundle")
            return false
        }

        guard let currentBuildID = Bundle.main.vbGuestBuildID else {
            logger.error("Couldn't find VBGuestBuildID in current bundle")
            return false
        }

        guard let currentBundleVersion = Bundle.main.bundleVersion else {
            logger.error("Couldn't find CFBundleVersion in current bundle")
            return false
        }

        guard imageBuildID != currentBuildID else {
            logger.debug("Image build ID is same as current build ID (\(currentBuildID, privacy: .public)), update won't be performed")
            return false
        }

        guard imageBundleVersion >= currentBundleVersion else {
            logger.debug("Image build ID differs from current build ID, but image has a lower CFBundleVersion (\(imageBundleVersion, privacy: .public)), ignoring")
            return false
        }

        logger.notice("Mounted image qualifies for update with CFBundleVersion \(imageBundleVersion, privacy: .public), VBGuestBuildID \(imageBuildID, privacy: .public)")

        return true
    }

}

extension Bundle {
    var bundleVersion: Int? {
        guard let str = infoDictionary?[kCFBundleVersionKey as String] as? String else { return nil }
        return Int(str)
    }
    var vbGuestBuildID: String? {
        infoDictionary?["VBGuestBuildID"] as? String
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
