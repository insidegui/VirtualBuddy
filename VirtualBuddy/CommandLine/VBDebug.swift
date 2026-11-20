import AppKit
import VirtualCore
import VirtualWormhole

@MainActor
enum VBDebug {
    static func main(_ arguments: [String]) async -> Never {
        do {
            switch arguments.first {
            case "extract" where arguments.count == 4:
                try DebugSymbolCache.extract(tool: URL(fileURLWithPath: arguments[1]), primary: URL(fileURLWithPath: arguments[2]), output: URL(fileURLWithPath: arguments[3]))
            case "prepare" where arguments.count == 2:
                try await prepare(URL(fileURLWithPath: arguments[1]))
            default: throw VBDebugError("Run vbdebug from a VirtualBuddy Xcode scheme.")
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data(("VirtualBuddy: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func prepare(_ scheme: URL) async throws {
        try DebugSocket.prepareRuntime()
        let xml = try XMLDocument(contentsOf: scheme, options: [.nodeLoadExternalEntitiesNever])
        guard let binding = DebugScheme.binding(in: xml) else { throw VBDebugError("Set up the Xcode scheme again in VirtualBuddy.") }
        let handoff = DebugSocket.runtime.appendingPathComponent(binding.scheme.uuidString + ".json")
        func record(_ reply: DebugBuildReply) throws { try JSONEncoder().encode(reply).write(to: handoff, options: .atomic) }
        try record(.failure("This Run action did not finish preparing the guest."))
        do {
            let settings = ProcessInfo.processInfo.environment
            let pref = CFPreferencesCopyAppValue("IDEDebuggerFeatureSetting" as CFString, "com.apple.dt.Xcode" as CFString) as? NSNumber
            guard (pref?.intValue ?? 0) & 12 == 12 else { throw VBDebugError("Enable Custom LLDB Commands using Set Up Xcode Debugging in VirtualBuddy, then relaunch Xcode.") }
            guard settings["PLATFORM_NAME"] == "macosx", let directory = settings["TARGET_BUILD_DIR"],
                  let name = settings["FULL_PRODUCT_NAME"], name.hasSuffix(".app"), let path = settings["EXECUTABLE_PATH"],
                  let developer = settings["DEVELOPER_DIR"] else { throw VBDebugError("Select My Mac and a macOS app target for this Run action.") }
            let base = URL(fileURLWithPath: directory), product = base.appendingPathComponent(name), executable = base.appendingPathComponent(path)
            guard executable.standardizedFileURL.path.hasPrefix(product.standardizedFileURL.path + "/"), FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw VBDebugError("Xcode did not build the selected app executable.")
            }
            let build = DebugBuild(vm: binding.vm, product: product, executable: executable, developer: URL(fileURLWithPath: developer), options: try DebugScheme.launchOptions(from: xml, settings: settings))
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            let host = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
            let url = DebugBroker.endpoint(pid: host.processIdentifier)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            var stream: DebugSocket?
            while stream == nil {
                stream = try? DebugSocket.unix(url, listening: false)
                if stream == nil {
                    guard !host.isTerminated, ContinuousClock.now < deadline else { throw VBDebugError("Open the version of VirtualBuddy that created this scheme and try again.") }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            guard let stream else { throw POSIXError(.ENOTCONN) }
            try await stream.send(build)
            let reply = try await stream.receive(DebugBuildReply.self)
            if case .failure(let reason) = reply { throw VBDebugError(reason) }
            try record(reply)
        } catch {
            try record(.failure(error.localizedDescription))
            throw error
        }
    }
}
