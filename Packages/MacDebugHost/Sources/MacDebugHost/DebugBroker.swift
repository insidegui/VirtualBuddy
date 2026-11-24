import Foundation
import MacDebugProtocol
import OSLog

struct DebugBuild: Codable {
    let destination: UUID
    let product: URL
    let executable: URL
    let developer: URL
    let automaticSigning: Bool
    let options: DebugLaunchOptions
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
    private let authorize: @MainActor () throws -> Void
    private let resolveDestination: @MainActor (UUID) async throws -> any RemoteDebugSession
    private var runs: [UUID: UUID] = [:]
    private var preparations: [UUID: Task<DebugHandoff, Error>] = [:]
    private var relays: [UUID: Task<Void, Never>] = [:]
    private var clients: [UUID: Task<Void, Never>] = [:]
    private var listenerTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "MacDebugHost", category: "DebugBroker")

    public init(
        configuration: DebugHostConfiguration,
        cache: DebugSymbolCache,
        provisioning: DebugProvisioning,
        authorize: @escaping @MainActor () throws -> Void,
        resolveDestination: @escaping @MainActor (UUID) async throws -> any RemoteDebugSession
    ) {
        self.configuration = configuration
        self.cache = cache
        self.provisioning = provisioning
        self.authorize = authorize
        self.resolveDestination = resolveDestination
    }

    public func stop() {
        guard let listenerTask else { return }
        listenerTask.cancel()
        self.listenerTask = nil
        unlink(configuration.endpoint(pid: getpid()).path)
        for client in clients.values { client.cancel() }
        for relay in relays.values { relay.cancel() }
    }

    public func start() throws {
        guard listenerTask == nil else { return }
        try DebugSocket.prepareRuntime(at: configuration.runtimeDirectory)
        let path = configuration.endpoint(pid: getpid())
        unlink(path.path)
        let listener = try DebugSocket.unix(path, listening: true)
        listenerTask = Task {
            while !Task.isCancelled {
                do {
                    let socket = try await listener.accept(timeout: -1)
                    try Task.checkCancellation()
                    let id = UUID()
                    clients[id] = Task {
                        defer { clients.removeValue(forKey: id) }
                        await serve(socket)
                    }
                } catch {
                    if !Task.isCancelled {
                        logger.error("Debugger listener: \(error.localizedDescription)")
                        stop()
                    }
                    return
                }
            }
        }
    }

    private func serve(_ socket: DebugSocket) async {
        do {
            let build = try await socket.receive(DebugBuild.self)
            try authorize()
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
