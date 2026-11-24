import Foundation
import MacDebugProtocol

public enum CustomLLDBCommands {
    static let key = "IDEDebuggerFeatureSetting"
    static let domain = "com.apple.dt.Xcode"
    static let mask = 12
    static var flags: Int { (CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber)?.intValue ?? 0 }
    public static var isEnabled: Bool { flags & mask == mask }

    public static func enable() throws {
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: flags | mask), domain as CFString)
        guard CFPreferencesAppSynchronize(domain as CFString), isEnabled else { throw MacDebugError("Could not enable Custom LLDB Commands in Xcode.") }
    }
}
