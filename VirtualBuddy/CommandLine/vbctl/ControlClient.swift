import AppKit
import MacDebugProtocol
import VirtualCore

/// The command-line tool's end of the control socket.
enum ControlClient {
    /// The app this tool is part of. The tool is the app's executable under another name,
    /// possibly reached through a link somewhere in the user's `PATH`.
    static var applicationURL: URL {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return Bundle.main.bundleURL }
        // VirtualBuddy.app/Contents/MacOS/VirtualBuddy
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return bundle.pathExtension == "app" ? bundle : Bundle.main.bundleURL
    }

    /// Sends a command to the app and returns what it answered, opening the app first if it has to.
    @MainActor
    static func perform(
        _ request: ControlRequest,
        launchingApp: Bool,
        onEvent: (String) -> Void
    ) async throws -> ControlPayload {
        let connection = try await connect(launchingApp: launchingApp)
        defer { connection.close() }

        do {
            try await connection.send(request)
            while true {
                switch try await connection.receive() {
                case .event(let message): onEvent(message)
                case .success(let payload): return payload
                case .failure(let error): throw error
                }
            }
        } catch let error as ControlError {
            throw error
        } catch is DecodingError {
            throw ControlError(.incompatibleVersion, "vbctl and the running copy of VirtualBuddy are different versions. Quit and reopen VirtualBuddy, then try again.")
        } catch {
            throw ControlError(.unreachable, "Lost the connection to VirtualBuddy. Command-line access may have been turned off, or the app quit.")
        }
    }

    @MainActor
    private static func connect(launchingApp: Bool) async throws -> ControlConnection {
        let url = ControlProtocol.socketURL
        if let connection = try ControlConnection.open(url) { return connection }

        // The socket only exists while command-line access is on, so there's nothing to wait for when it's off.
        if CommandLineAccess.isDisabledByOrganization {
            throw ControlError(.accessDisabled, "Command-line access is disabled by your organization.")
        }
        guard CommandLineAccess.isEnabled else {
            throw ControlError(.accessDisabled, "Command-line access is turned off. Enable it in VirtualBuddy Settings → Security.")
        }

        var app = runningApplication
        if app == nil {
            guard launchingApp else { throw ControlError(.unreachable, "VirtualBuddy isn't running.") }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            do {
                app = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
            } catch {
                throw ControlError(.unreachable, "Couldn't open VirtualBuddy. \(error.localizedDescription)")
            }
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while true {
            if let connection = try ControlConnection.open(url) { return connection }
            guard app?.isTerminated != true else { throw ControlError(.unreachable, "VirtualBuddy quit before it answered.") }
            guard ContinuousClock.now < deadline else {
                throw ControlError(.unreachable, "VirtualBuddy isn't accepting command-line connections. Make sure command-line access is enabled in VirtualBuddy Settings → Security.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private static var runningApplication: NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { $0.processIdentifier != current && !$0.isTerminated }
    }
}

/// A connection to the app's control socket, from the side that asks.
final class ControlConnection: Sendable {
    private let socket: DebugSocket

    private init(_ socket: DebugSocket) { self.socket = socket }

    /// Connects to the socket, or returns `nil` when nothing is listening there.
    ///
    /// What comes back decides what the tool reports and does next, so whatever answers has to be the app itself.
    static func open(_ url: URL) throws -> ControlConnection? {
        guard let socket = try? DebugSocket.unix(url, listening: false) else { return nil }
        do {
            try socket.requirePeer(.currentApplication())
        } catch {
            socket.stop()
            throw ControlError(.unreachable, "Couldn't verify that VirtualBuddy is what answered. Quit and reopen VirtualBuddy, then try again.")
        }
        return ControlConnection(socket)
    }

    func send<Message: Encodable>(_ message: Message) async throws {
        try await socket.send(message)
    }

    func receive() async throws -> ControlReply {
        try await socket.receive(ControlReply.self)
    }

    func close() { socket.stop() }
}
