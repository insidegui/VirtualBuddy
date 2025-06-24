import Foundation

extension String {
    static let appleOSBuildRegex = /[0-9]{2}[A-Z][0-9]{2,}[a-z]?/

    /// Returns the first regex match for an Apple OS build number (ex: `23A5276f`).
    func matchAppleOSBuild() -> String? {
        (try? Self.appleOSBuildRegex.firstMatch(in: self)?.output).flatMap { String($0) }
    }
}
