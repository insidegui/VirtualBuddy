import SwiftUI
import VirtualCore
import VirtualUI
import BuddyFoundation

/**
 Main entry point for the VirtualBuddy app and all supported command-line tools.

 Command-line tools are implemented using ArgumentParser and declared in ``VirtualBuddyCLI``.

 The app target symlinks the VirtualBuddy app executable with the names of each supported command-line tool
 as part of a run script build phase.

 This entry point uses ``VirtualBuddyCLI`` to check if the current executable name matches that of a supported command-line tool.
 If that's the case, ``VirtualBuddyCLI`` will invoke the tool's implementation and skip running the app itself.
 */
@main
struct VirtualBuddyEntryPoint {
    static func main() async throws {
        let name: String

        #if DEBUG
        /**
         `VB_TOOL` environment variable can be used to test command-line tools when running from within Xcode,
         where it is inconvenient to deal with running the symlinked variants.

         Each tool should have an aggregate target set up in the project that has this environment variable set.
         */
        if let overrideName = ProcessInfo.processInfo.environment["VB_TOOL"] {
            name = overrideName
        } else {
            name = ProcessInfo.processInfo.processName
        }
        #else
        name = ProcessInfo.processInfo.processName
        #endif

        /// Only attempt to process commands if the executable name doesn't match the name in the app bundle.
        guard name != Bundle.main.executableName else {
            return VirtualBuddyApp.main()
        }

        await VirtualBuddyCLI.runCommand(named: name)

        VirtualBuddyApp.main()
    }
}

private extension Bundle {
    /**
     For the purposes of checking whether the user is running the VirtualBuddy app or a command-line tool,
     the actual bundle executable declared in the `Info.plist` must be compared against the process name.

     The `Bundle.executableURL` property will return the URL of the actual executable symlink instead of the one declared.
     */
    var executableName: String { infoDictionary?["CFBundleExecutable"] as? String ?? "VirtualBuddy" }
}
