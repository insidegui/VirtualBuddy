import AppKit
import MacDebugProtocol

@MainActor
public enum DebugHostCommand {
    public static func run(_ arguments: [String], configuration: DebugHostConfiguration) async throws {
        switch arguments.first {
        case "extract" where arguments.count == 4:
            try DebugSymbolCache.extract(tool: URL(fileURLWithPath: arguments[1]), primary: URL(fileURLWithPath: arguments[2]), output: URL(fileURLWithPath: arguments[3]))
        case "prepare" where arguments.count == 2:
            try await prepare(URL(fileURLWithPath: arguments[1]), configuration: configuration)
        default: throw MacDebugError("Run the debug helper from a generated Xcode scheme.")
        }
    }

    private static func prepare(_ scheme: URL, configuration: DebugHostConfiguration) async throws {
        try DebugSocket.prepareRuntime(at: configuration.runtimeDirectory)
        let xml = try XMLDocument(contentsOf: scheme, options: [.nodeLoadExternalEntitiesNever])
        guard let binding = DebugScheme.binding(in: xml) else { throw MacDebugError("Set up the Xcode scheme again.") }
        let handoff = configuration.runtimeDirectory.appendingPathComponent(binding.scheme.uuidString + ".json")
        func record(_ reply: DebugBuildReply) throws { try JSONEncoder().encode(reply).write(to: handoff, options: .atomic) }
        try record(.failure("This Run action did not finish preparing the target."))
        do {
            let settings = ProcessInfo.processInfo.environment
            guard CustomLLDBCommands.isEnabled else { throw MacDebugError("Enable Custom LLDB Commands in Xcode debugging setup, then relaunch Xcode.") }
            guard settings["PLATFORM_NAME"] == "macosx", let directory = settings["TARGET_BUILD_DIR"],
                  let name = settings["FULL_PRODUCT_NAME"], name.hasSuffix(".app"), let path = settings["EXECUTABLE_PATH"],
                  let developer = settings["DEVELOPER_DIR"] else { throw MacDebugError("Select My Mac and a macOS app target for this Run action.") }
            let base = URL(fileURLWithPath: directory), product = base.appendingPathComponent(name), executable = base.appendingPathComponent(path)
            guard executable.standardizedFileURL.path.hasPrefix(product.standardizedFileURL.path + "/"), FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw MacDebugError("Xcode did not build the selected app executable.")
            }
            let build = DebugBuild(destination: binding.destination, product: product, executable: executable, developer: URL(fileURLWithPath: developer), options: try DebugScheme.launchOptions(from: xml, settings: settings))
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            let host = try await NSWorkspace.shared.openApplication(at: configuration.applicationURL, configuration: config)
            let url = configuration.endpoint(pid: host.processIdentifier)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            var stream: DebugSocket?
            while stream == nil {
                stream = try? DebugSocket.unix(url, listening: false)
                if stream == nil {
                    guard !host.isTerminated, ContinuousClock.now < deadline else { throw MacDebugError("Open the app that created this scheme and try again.") }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            guard let stream else { throw POSIXError(.ENOTCONN) }
            try await stream.send(build)
            let reply = try await stream.receive(DebugBuildReply.self)
            if case .failure(let reason) = reply { throw MacDebugError(reason) }
            try record(reply)
        } catch {
            try record(.failure(error.localizedDescription))
            throw error
        }
    }
}
