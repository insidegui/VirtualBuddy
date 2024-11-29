import Foundation
import AppKit
@_spi(GuestEnvironment) import VirtualCore

@MainActor
@main
struct GuestApp {
    static func main() {
        ProcessInfo._isVirtualBuddyHost.withLock { $0 = false }
        ProcessInfo._isVirtualBuddyGuest.withLock { $0 = true }

        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
