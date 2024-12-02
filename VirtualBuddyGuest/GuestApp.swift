import Foundation
import AppKit
@_spi(GuestEnvironment) import VirtualCore

@MainActor
@main
struct GuestApp {
    static func main() {
        ProcessInfo._isVirtualBuddyHost.withLock { $0 = false }
        ProcessInfo._isVirtualBuddyGuest.withLock { $0 = true }

        #if DEBUG
        /// Always enable verbose logging for debug guest running in virtual machine.
        if ProcessInfo.processInfo.isVirtualMachine {
            UserDefaults.standard
                .setVolatileDomain(
                    [kVirtualMessagingVerboseFlag: true],
                    forName: UserDefaults.argumentDomain
                )
        }
        #endif

        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
