import Foundation
import MacDebugHost
import VirtualCore

@MainActor
enum VBDebug {
    static func main(_ arguments: [String]) async -> Never {
        do {
            try await DebugHostCommand.run(arguments, configuration: VirtualBuddyDebugging.host)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data(("VirtualBuddy: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
