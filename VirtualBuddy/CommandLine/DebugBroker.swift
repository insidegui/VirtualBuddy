import AppKit
import VirtualCore
import VirtualUI
import VirtualWormhole
import Virtualization
import OSLog

struct DebugBuild: Codable {
    let vm: UUID
    let product: URL
    let executable: URL
    let developer: URL
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
final class DebugBroker {
    private let library: VMLibraryController
    private var runs: [UUID: UUID] = [:]
    private var relays: [UUID: Task<Void, Never>] = [:]
    private var listenerTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "codes.rambo.VirtualBuddy", category: "DebugBroker")

    init(library: VMLibraryController) { self.library = library }
    static func endpoint(pid: pid_t) -> URL { DebugSocket.runtime.appendingPathComponent("host-\(pid).sock") }

    func stop() {
        listenerTask?.cancel()
        listenerTask = nil
        unlink(Self.endpoint(pid: getpid()).path)
    }

    func start() {
        do {
            try DebugSocket.prepareRuntime()
            let path = Self.endpoint(pid: getpid())
            unlink(path.path)
            let listener = try DebugSocket.unix(path, listening: true)
            listenerTask = Task {
                defer { unlink(path.path) }
                while !Task.isCancelled {
                    do {
                        let socket = try await listener.accept(timeout: -1)
                        Task { await self.serve(socket) }
                    } catch {
                        if !Task.isCancelled { logger.error("Debugger listener: \(error.localizedDescription)") }
                        break
                    }
                }
            }
        } catch { logger.error("Could not start Xcode debugging: \(error.localizedDescription)") }
    }

    private func serve(_ socket: DebugSocket) async {
        do {
            let build = try await socket.receive(DebugBuild.self)
            guard VBSettings.current.developerFeaturesEnabled else {
                throw VBDebugError("Enable Developer Features in VirtualBuddy Settings → Developer to run this Xcode scheme.")
            }
            guard runs[build.vm] == nil else { throw VBDebugError("A debug run is active in this VM. Stop it in Xcode before launching again.") }
            let run = UUID()
            runs[build.vm] = run
            let prepare = Task { try await self.prepare(build, run: run) }
            let disconnect = Task {
                _ = try? await socket.read(upTo: 1)
                if !Task.isCancelled { prepare.cancel() }
            }
            defer { disconnect.cancel() }
            do {
                let ready = try await prepare.value
                do {
                    try await socket.send(DebugBuildReply.ready(ready))
                } catch {
                    // The Xcode pre-action went away before receiving the rendezvous.
                    relays[run]?.cancel()
                    await relays[run]?.value
                }
            } catch {
                finish(build.vm, run: run)
                try? await socket.send(DebugBuildReply.failure(error.localizedDescription))
            }
        } catch { try? await socket.send(DebugBuildReply.failure(error.localizedDescription)) }
    }

    private func finish(_ vm: UUID, run: UUID) {
        if runs[vm] == run { runs[vm] = nil }
        relays[run] = nil
        DebugSymbolCache.shared.release(run)
    }

    private func prepare(_ build: DebugBuild, run: UUID) async throws -> DebugHandoff {
        let ui = try await VirtualMachineSessionUIManager.shared.sessionForDebugging(build.vm, library: library)
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while ui.controller.debugGuestSession?.isConnected != true {
            guard ui.controller.state.isRunning, ContinuousClock.now < deadline else {
                throw VBDebugError("Log in to the VM and open the current VirtualBuddyGuest app, then run again.")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard let session = ui.controller.debugGuestSession, session.supportsDebugging else {
            throw VBDebugError("Install the current VirtualBuddyGuest from the guest additions disk and open it in the VM.")
        }
        do {
            let images = try await session.prepareDebugRun(run)
            let cacheTask = Task { try await DebugSymbolCache.shared.acquire(images, session: session, run: run, developer: build.developer) { self.cacheTasks[run]?.cancel() } }
            cacheTasks[run] = cacheTask
            defer { cacheTasks.removeValue(forKey: run) }
            let sysroot = try await withTaskCancellationHandler { try await cacheTask.value } onCancel: { cacheTask.cancel() }
            let zip = FileManager.default.temporaryDirectory.appendingPathComponent(run.uuidString + ".zip")
            defer { try? FileManager.default.removeItem(at: zip) }
            try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--sequesterRsrc", "--keepParent", build.product.path, zip.path])
            let endpoint = try await session.launchDebugApp(zip, options: build.options, run: run)
            let connection = try await ui.controller.connectDebugger(to: endpoint.port)
            let remote = try DebugSocket(owning: dup(connection.fileDescriptor))
            let token = try await withThrowingTaskGroup(of: UUID.self) { group in
                group.addTask { try await remote.receive(UUID.self) }
                group.addTask { try await Task.sleep(for: .seconds(10)); throw POSIXError(.ETIMEDOUT) }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            guard token == run else { throw VBDebugError("Unexpected debugger session from the VM.") }
            let url = DebugSocket.runtime.appendingPathComponent(run.uuidString + ".sock")
            try Task.checkCancellation()
            let listener = try DebugSocket.unix(url, listening: true)
            relays[run] = Task {
                do {
                    let local = try await listener.accept(timeout: 90000)
                    unlink(url.path)
                    await DebugSocket.relay(local, remote)
                } catch { logger.debug("Debug relay ended: \(error.localizedDescription)") }
                withExtendedLifetime(connection) {}
                remote.stop()
                unlink(url.path)
                await session.cancelDebugRun(run)
                finish(build.vm, run: run)
            }
            let symbols = sysroot.appendingPathComponent("\(images.version) (\(images.build))/Symbols")
            return .init(executable: build.executable.path, product: build.product.path, guestProduct: endpoint.bundlePath, sysroot: sysroot.path, symbols: symbols.path, socket: url.path)
        } catch {
            // A cancelled transport request cannot cancel its own remote operation.
            await Task { await session.cancelDebugRun(run) }.value
            throw error
        }
    }
    private var cacheTasks: [UUID: Task<URL, Error>] = [:]
}
