import Foundation
import os

public extension UserDefaults {
    static let isGuestSimulationEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["GUEST_SIMULATION_ENABLED"] == "1"
            || UserDefaults.standard.bool(forKey: "GuestSimulationEnabled")
        #else
        return false
        #endif
    }()
}

public extension ProcessInfo {
    /// `true` if running in VirtualBuddy on the host OS.
    ///
    /// - note: Not autodetected. App must set `_isVirtualBuddyHost` (via SPI).
    var isVirtualBuddyHost: Bool { Self._isVirtualBuddyHost.withLock { $0 } }

    /// `true` if running in VirtualBuddyGuest on the guest OS.
    ///
    /// - note: Not autodetected. App must set `_isVirtualBuddyGuest` (via SPI).
    var isVirtualBuddyGuest: Bool { Self._isVirtualBuddyGuest.withLock { $0 } }

    /// `true` if running in VirtualBuddyGuest on the host OS for debug simulation purposes.
    ///
    /// - note: Not autodetected. App must set `_isVirtualBuddyGuest` (via SPI).
    var isVirtualBuddyGuestSimulator: Bool {
        #if DEBUG
        return UserDefaults.isGuestSimulationEnabled && Self._isVirtualBuddyGuest.withLock { $0 }
        #else
        return false
        #endif
    }
}

extension ProcessInfo {
    @_spi(GuestEnvironment)
    public nonisolated(unsafe) static var _isVirtualBuddyHost = OSAllocatedUnfairLock(initialState: false)

    @_spi(GuestEnvironment)
    public nonisolated(unsafe) static var _isVirtualBuddyGuest = OSAllocatedUnfairLock(initialState: false)
}
