import Foundation

public struct VirtualInstallation {
    /// Returns `true` if VirtualInstallation is available in the current system.
    static let isAvailable = MobileDeviceHelper.verifyMobileDeviceSoftLink()
}
