import Foundation
import MacDebugHost

public enum VirtualBuddyDebugging {
    public static let host = DebugHostConfiguration(
        applicationURL: Bundle.main.bundleURL,
        helperURL: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/vbdebug"),
        runtimeDirectory: URL(fileURLWithPath: "/private/tmp/vbdebug-\(getuid())", isDirectory: true)
    )

    public static let bindings = KeychainDebugBindingStore(
        service: (Bundle.main.bundleIdentifier ?? "codes.rambo.VirtualBuddy") + ".debug-bindings"
    )

    @MainActor public static let symbolCache = DebugSymbolCache(
        root: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("codes.rambo.VirtualBuddy/DebugSymbols"),
        helperURL: host.helperURL
    )
}
