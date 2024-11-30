import Foundation
import os

public extension UserDefaults {
    /// [HOST AND GUEST] Enables running guest app on host for debugging,
    /// displays debug UI for simulated guest on host app launch.
    static let isGuestSimulationEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["GUEST_SIMULATION_ENABLED"] == "1"
            || UserDefaults.standard.bool(forKey: "GuestSimulationEnabled")
        #else
        return false
        #endif
    }()

    /// [HOST ONLY] Disables automatic bootstrap of guest service clients, enables debug UI.
    static let isGuestDebuggingEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["GUEST_DEBUGGING_ENABLED"] == "1"
            || UserDefaults.standard.bool(forKey: "GuestDebuggingEnabled")
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

    /// `true` if the app is running in a virtual machine.
    ///
    /// In debug builds, setting the `VB_FAKE_VM` environment variable to `1` forces this to `true`.
    var isVirtualMachine: Bool { Self._isVirtualMachine }
}

// MARK: - Environment SPI

extension ProcessInfo {
    @_spi(GuestEnvironment)
    public nonisolated(unsafe) static var _isVirtualBuddyHost = OSAllocatedUnfairLock(initialState: false)

    @_spi(GuestEnvironment)
    public nonisolated(unsafe) static var _isVirtualBuddyGuest = OSAllocatedUnfairLock(initialState: false)
}

// MARK: - Sysctl

private extension ProcessInfo {
    static let _isVirtualMachine: Bool = {
        #if DEBUG
        if processInfo.environment["VB_FAKE_VM"] == "1" {
            return true
        }
        #endif

        var size: size_t = 4

        var vmmPresent: Int = 0
        sysctlbyname("kern.hv_vmm_present", &vmmPresent, &size, nil, 0)

        return vmmPresent == 1
    }()
}
