import Foundation
import BuddyFoundation

/// A representation of the MobileDevice framework and its properties.
public struct MobileDeviceFramework: Sendable {
    /// The version of the MobileDevice framework.
    public let version: SoftwareVersion

    /// The MobileDevice framework in the current system, or `nil` if it couldn't be found
    /// or its properties couldn't be parsed.
    public static var current: MobileDeviceFramework? {
        MobileDeviceFramework()
    }
}

private extension MobileDeviceFramework {
    init?() {
        let path = "/System/Library/PrivateFrameworks/MobileDevice.framework"
        guard let bundle = Bundle(path: path) else {
            assertionFailure("MobileDevice.framework not found at \(path)")
            return nil
        }

        guard let info = bundle.infoDictionary else {
            assertionFailure("MobileDevice.framework is missing an info dictionary")
            return nil
        }

        guard let rawVersion = info[kCFBundleVersionKey as String] as? String else {
            assertionFailure("MobileDevice.framework has missing or invalid CFBundleVersion")
            return nil
        }

        guard let version = SoftwareVersion(string: rawVersion) else {
            assertionFailure("MobileDevice.framework has invalid CFBundleVersion: \(rawVersion)")
            return nil
        }

        self.init(version: version)
    }
}
