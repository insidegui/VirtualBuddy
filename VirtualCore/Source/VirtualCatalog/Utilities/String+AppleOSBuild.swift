import Foundation
import BuddyFoundation

extension String {
    static let appleOSBuildRegex = /[0-9]{2}[A-Z][0-9]{2,}[a-z]?/
    static let appleOSVersionRegex = /[0-9]+(?:\.[0-9]+){1,2}/

    /// Returns the first regex match for an Apple OS build number (ex: `23A5276f`).
    func matchAppleOSBuild() -> String? {
        (try? Self.appleOSBuildRegex.firstMatch(in: self)?.output).flatMap { String($0) }
    }

    /// Returns the first regex match for an Apple OS version (ex: `15.5` or `15.5.1`).
    func matchAppleOSVersion() -> SoftwareVersion? {
        (try? Self.appleOSVersionRegex.firstMatch(in: self)?.output)
            .flatMap { SoftwareVersion(string: String($0)) }
    }
}
