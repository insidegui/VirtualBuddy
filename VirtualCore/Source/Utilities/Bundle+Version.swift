import Foundation

public extension Bundle {
    var vbShortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var vbVersion: SoftwareVersion {
        SoftwareVersion(string: vbShortVersionString) ?? SoftwareVersion.empty
    }

    var vbBuild: Int {
        let str = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return Int(str) ?? 0
    }
}
