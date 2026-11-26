import Foundation
import MacDebugProtocol
import OSLog
import VirtualCore

/// Answers the `vbctl` command-line tool over a Unix socket that only exists while command-line access is on.
///
/// Every connection has to come from this app's own executable, which is what the tool is. The kernel records
/// the audit token of the process that connected, and the code it identifies is checked against the app's own
/// designated requirement, so nothing else can speak to the socket even though it's in a folder the user can reach.
///
/// That check establishes what's on the other end, not who started it: anything running as the user can run the tool.
/// It's why the socket is opt-in, and why no command can approve a service tunnel or change a security setting.
@MainActor
final class ControlServer {
    typealias Handler = @MainActor (ControlRequest, _ report: @escaping @MainActor (String) async -> Void) async throws -> ControlPayload

    private static let clientLimit = 16
    private let logger = Logger(for: ControlServer.self)
    private let socketURL: URL
    private let runtimeDirectory: URL
    private let authorize: @MainActor () throws -> Void
    private let handler: Handler
    private var listener: Task<Void, Never>?
    private var clients: [UUID: Task<Void, Never>] = [:]

    init(
        socketURL: URL = ControlProtocol.socketURL,
        runtimeDirectory: URL = ControlProtocol.runtimeDirectory,
        authorize: @escaping @MainActor () throws -> Void,
        handler: @escaping Handler
    ) {
        self.socketURL = socketURL
        self.runtimeDirectory = runtimeDirectory
        self.authorize = authorize
        self.handler = handler
    }

    var isListening: Bool { listener != nil }

    func start() throws {
        guard listener == nil else { return }
        try DebugSocket.prepareRuntime(at: runtimeDirectory)
        unlink(socketURL.path)
        let peer = try DebugPeerRequirement.currentApplication()
        let server = try DebugSocket.unix(socketURL, listening: true)
        logger.notice("Accepting command-line connections")
        listener = Task { [weak self] in
            var delay = Duration.milliseconds(50)
            while !Task.isCancelled {
                do {
                    let socket = try await server.accept(timeout: -1) { _, _ in }
                    self?.accept(socket, from: peer)
                    delay = .milliseconds(50)
                } catch is CancellationError {
                    break
                } catch {
                    self?.logger.error("Could not accept a command-line connection: \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, .seconds(1))
                }
            }
        }
    }

    /// Closes the socket and drops every connection, including commands that are waiting for something.
    func stop() {
        guard let listener else { return }
        listener.cancel()
        self.listener = nil
        clients.values.forEach { $0.cancel() }
        clients.removeAll()
        unlink(socketURL.path)
        logger.notice("No longer accepting command-line connections")
    }

    private func accept(_ socket: DebugSocket, from peer: DebugPeerRequirement) {
        guard clients.count < Self.clientLimit else {
            logger.error("Refused a command-line connection because too many are open")
            return socket.stop()
        }
        let id = UUID()
        clients[id] = Task { [weak self] in
            do {
                try socket.requirePeer(peer)
                await self?.serve(socket)
            } catch {
                self?.logger.error("Refused a command-line connection from a process that isn't this app's tool")
            }
            socket.stop()
            self?.clients[id] = nil
        }
    }

    private func serve(_ socket: DebugSocket) async {
        // Cancelling a read shuts the socket down, so the watcher below is only cancelled once the reply was sent.
        var disconnection: Task<Void, Never>?
        defer { disconnection?.cancel() }

        let reply: ControlReply
        do {
            let request = try await receiveRequest(from: socket)
            // The setting is read again for every request: the socket closing isn't what enforces it.
            try authorize()
            guard request.version == ControlProtocol.version else {
                throw ControlError(.incompatibleVersion, "vbctl and the running copy of VirtualBuddy are different versions. Quit and reopen VirtualBuddy, then try again.")
            }

            let handler = self.handler
            let work = Task { @MainActor in
                try await handler(request) { message in
                    try? await socket.send(ControlReply.event(message))
                }
            }
            // The tool sends nothing after its request, so this read only ever ends when it goes away,
            // which is when a command that's waiting for something has nobody left to wait for.
            disconnection = Task {
                _ = try? await socket.read(upTo: 1)
                work.cancel()
            }

            reply = .success(try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            })
        } catch is CancellationError {
            return
        } catch let error as ControlError {
            reply = .failure(error)
        } catch {
            reply = .failure(ControlError(.failure, error.localizedDescription))
        }
        try? await socket.send(reply)
    }

    private func receiveRequest(from socket: DebugSocket) async throws -> ControlRequest {
        do {
            return try await socket.receive(ControlRequest.self, within: .seconds(10))
        } catch is DecodingError {
            throw ControlError(.incompatibleVersion, "This copy of VirtualBuddy doesn't understand the command. Quit and reopen VirtualBuddy, then try again.")
        }
    }
}
