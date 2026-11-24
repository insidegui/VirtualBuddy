import Foundation
import MacDebugProtocol
import OSLog

/// What the scheme's pre-action asks for. The sender is unprivileged, so every field is
/// validated and the destination comes from the binding the developer approved.
struct DebugBuildRequest: Codable, Sendable {
    let binding: UUID
    let product: URL
    let executable: URL
    let developer: URL
    let automaticSigning: Bool
    let options: DebugLaunchOptions
}

struct DebugBuild {
    let destination: UUID
    let product: URL
    let executable: URL
    let developer: URL
    let automaticSigning: Bool
    let options: DebugLaunchOptions

    init(_ request: DebugBuildRequest, binding: DebugBinding) throws {
        func local(_ url: URL) throws -> URL {
            guard url.isFileURL, url.path.hasPrefix("/") else { throw MacDebugError("The Run action sent an invalid build location.") }
            return url.standardizedFileURL
        }
        guard request.binding == binding.id else { throw MacDebugError("The Run action does not match its Xcode scheme.") }
        destination = binding.destination
        product = try local(request.product)
        executable = try local(request.executable)
        developer = try local(request.developer)
        guard product.pathExtension == "app", executable.path.hasPrefix(product.path + "/") else {
            throw MacDebugError("The Run action must build a macOS app.")
        }
        automaticSigning = request.automaticSigning
        options = request.options
    }
}

struct DebugHandoff: Codable {
    let executable: String
    let product: String
    let guestProduct: String
    let sysroot: String
    let symbols: String
    let socket: String
}

enum DebugBuildReply: Codable {
    case ready(DebugHandoff)
    case failure(String)
}

@MainActor
public final class DebugBroker {
    private let configuration: DebugHostConfiguration
    private let cache: DebugSymbolCache
    private let provisioning: DebugProvisioning
    private let bindings: any DebugBindingStore
    private let authorize: @MainActor () throws -> Void
    private let resolveDestination: @MainActor (UUID) async throws -> any RemoteDebugSession
    private var runs: [UUID: UUID] = [:]
    private var preparations: [UUID: Task<DebugHandoff, Error>] = [:]
    private var relays: [UUID: Task<Void, Never>] = [:]
    private var clients: [UUID: Task<Void, Never>] = [:]
    private var listenerTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "MacDebugHost", category: "DebugBroker")
    /// A client stays connected while its run is prepared, so this also bounds concurrent preparations.
    var clientLimit = 16
    /// The helper sends its request as soon as it connects.
    var requestTimeout = Duration.seconds(10)

    public init(
        configuration: DebugHostConfiguration,
        cache: DebugSymbolCache,
        provisioning: DebugProvisioning,
        bindings: any DebugBindingStore,
        authorize: @escaping @MainActor () throws -> Void,
        resolveDestination: @escaping @MainActor (UUID) async throws -> any RemoteDebugSession
    ) {
        self.configuration = configuration
        self.cache = cache
        self.provisioning = provisioning
        self.bindings = bindings
        self.authorize = authorize
        self.resolveDestination = resolveDestination
    }

    /// Closes the listener and ends every run. Use this when the app shuts down.
    public func stop() {
        stopListening()
        for client in clients.values { client.cancel() }
        for relay in relays.values { relay.cancel() }
    }

    /// Closes the listener so no new run can be requested. Runs that are already
    /// debugging continue, and runs still being prepared end at their next authorization check.
    public func stopListening() {
        guard let listenerTask else { return }
        listenerTask.cancel()
        self.listenerTask = nil
        unlink(configuration.endpoint(pid: getpid()).path)
    }

    public func start() throws {
        guard listenerTask == nil else { return }
        try DebugSocket.prepareRuntime(at: configuration.runtimeDirectory)
        do {
            try configuration.refreshLinks()
        } catch {
            // Links from an earlier launch may still be right, so keep accepting runs.
            logger.error("Could not update the links used by Xcode schemes: \(error.localizedDescription)")
        }
        let path = configuration.endpoint(pid: getpid())
        unlink(path.path)
        // Only the helper shipped in this app may request runs. It is the same signed
        // code as the app, so it satisfies the app's own designated requirement.
        let helper = try DebugPeerRequirement.currentApplication()
        let listener = try DebugSocket.unix(path, listening: true)
        listenerTask = Task {
            var failures = 0
            while !Task.isCancelled {
                do {
                    // Peers are checked per connection, so a rejected one cannot end the listener.
                    let socket = try await listener.accept(timeout: -1) { _, _ in }
                    try Task.checkCancellation()
                    failures = 0
                    accept(socket, from: helper)
                } catch {
                    guard !Task.isCancelled else { return }
                    // Failures such as running out of file descriptors pass, so the listener
                    // waits and tries again instead of staying down until the app restarts.
                    failures += 1
                    logger.error("Debugger listener: \(error.localizedDescription)")
                    try? await Task.sleep(for: .milliseconds(min(250 << min(failures, 5), 5000)))
                }
            }
        }
    }

    private func accept(_ socket: DebugSocket, from helper: DebugPeerRequirement) {
        guard clients.count < clientLimit else {
            logger.error("Refused a debugger connection because too many are open.")
            return
        }
        let id = UUID()
        clients[id] = Task {
            defer { clients.removeValue(forKey: id) }
            do {
                try socket.requirePeer(helper)
            } catch {
                logger.error("Rejected a debugger connection from an unrecognized process.")
                return
            }
            await serve(socket)
        }
    }

    private func serve(_ socket: DebugSocket) async {
        do {
            let request = try await socket.receive(DebugBuildRequest.self, within: requestTimeout)
            try authorize()
            guard let binding = try bindings.binding(for: request.binding) else {
                throw MacDebugError("This Xcode scheme has not been approved. Set up Xcode debugging for it again.")
            }
            let build = try DebugBuild(request, binding: binding)
            guard runs[build.destination] == nil else { throw MacDebugError("A debug run is active on this destination. Stop it in Xcode before launching again.") }
            let run = UUID()
            runs[build.destination] = run
            let prepare = Task { try await self.prepare(build, run: run) }
            preparations[run] = prepare
            defer { preparations.removeValue(forKey: run) }
            let disconnect = Task {
                _ = try? await socket.read(upTo: 1)
                if !Task.isCancelled { prepare.cancel() }
            }
            defer { disconnect.cancel() }
            do {
                let ready = try await withTaskCancellationHandler {
                    try await prepare.value
                } onCancel: {
                    prepare.cancel()
                }
                do {
                    try await socket.send(DebugBuildReply.ready(ready))
                } catch {
                    // The Xcode pre-action went away before receiving the rendezvous.
                    relays[run]?.cancel()
                    await relays[run]?.value
                }
            } catch {
                finish(build.destination, run: run)
                try? await socket.send(DebugBuildReply.failure(error.localizedDescription))
            }
        } catch { try? await socket.send(DebugBuildReply.failure(error.localizedDescription)) }
    }

    private func finish(_ destination: UUID, run: UUID) {
        if runs[destination] == run { runs[destination] = nil }
        relays[run] = nil
        cache.release(run)
    }

    private func prepare(_ build: DebugBuild, run: UUID) async throws -> DebugHandoff {
        let session = try await resolveDestination(build.destination)
        do {
            let images = try await session.prepareDebugRun(run)
            let cancel: @MainActor @Sendable () -> Void = { self.preparations[run]?.cancel() }
            let (sysroot, bundlePath, remote) = try await DebugTools.withTemporaryDirectory { @MainActor work in
                let product = try await self.provisioning.prepare(build, session: session, run: run, work: work, cancel: cancel)
                let sysroot = try await self.cache.acquire(images, session: session, destinationID: build.destination, run: run,
                                                          developer: build.developer, cancel: cancel)
                let zip = work.appendingPathComponent("Application.zip")
                try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--sequesterRsrc", "--keepParent", product.path, zip.path])
                try self.authorize()
                let (path, remote) = try await session.launch(zip, options: build.options, run: run)
                return (sysroot, path, remote)
            }
            let url = configuration.runtimeDirectory.appendingPathComponent(run.uuidString + ".sock")
            try Task.checkCancellation()
            let listener = try DebugSocket.unix(url, listening: true)
            relays[run] = Task {
                do {
                    let local = try await listener.accept(timeout: 90000)
                    unlink(url.path)
                    await DebugSocket.relay(local, remote)
                } catch { logger.debug("Debug relay ended: \(error.localizedDescription)") }
                remote.stop()
                unlink(url.path)
                await session.cancelDebugRun(run)
                finish(build.destination, run: run)
            }
            let symbols = sysroot.appendingPathComponent("\(images.version) (\(images.build))/Symbols")
            return .init(executable: build.executable.path, product: build.product.path, guestProduct: bundlePath, sysroot: sysroot.path, symbols: symbols.path, socket: url.path)
        } catch {
            // A cancelled transport request cannot cancel its own remote operation.
            await Task { await session.cancelDebugRun(run) }.value
            throw error
        }
    }
}
