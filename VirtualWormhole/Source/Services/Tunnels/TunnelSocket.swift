import Darwin
import Foundation
import MacDebugProtocol

/// Remembers the socket files that listeners in this app created.
///
/// A listener removes its socket file when it stops, but not when the app is killed or the machine it runs on is
/// shut down. The file left behind would keep the next listener from starting, and can't simply be deleted,
/// because a socket at that path could just as well belong to something else. A file is only this app's to
/// replace when it's still the one recorded here.
final class TunnelSocketFiles: @unchecked Sendable {
    static let shared = TunnelSocketFiles(defaults: .standard)

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let key = "ServiceTunnelSocketFiles"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func update(_ change: (inout [String: String]) -> Void) {
        lock.withLock {
            var files = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
            change(&files)
            defaults.set(files, forKey: key)
        }
    }

    func record(_ path: String, _ info: stat) {
        update { $0[path] = String(info.st_ino) }
    }

    func forget(_ path: String) {
        update { $0[path] = nil }
    }

    /// Removes the socket file at the path if a listener in this app created it and nothing is listening on it anymore.
    func removeAbandonedSocket(at path: String) {
        let recorded = lock.withLock { (defaults.dictionary(forKey: key) as? [String: String])?[path] }
        var info = stat()
        guard let recorded, lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == getuid(), String(info.st_ino) == recorded else { return }
        // Another virtual machine's listener may still be serving this path.
        do {
            _ = try TunnelEndpoint.unix(path).open(listening: false, connectTimeout: 250)
            return
        } catch let error as POSIXError where error.code == .ECONNREFUSED {
        } catch {
            return
        }
        var current = stat()
        guard lstat(path, &current) == 0, current.st_dev == info.st_dev, current.st_ino == info.st_ino else { return }
        unlink(path)
        forget(path)
    }
}

/// Owns the listening socket and its filesystem entry for exactly one rule.
final class TunnelListener {
    let socket: DebugSocket
    private var source: DispatchSourceRead?
    private var file: (String, stat)?
    private let socketFiles: TunnelSocketFiles

    init(_ endpoint: TunnelEndpoint, socketFiles: TunnelSocketFiles = .shared) throws {
        self.socketFiles = socketFiles
        if case .unix(let path) = endpoint {
            socketFiles.removeAbandonedSocket(at: path)
            socket = try endpoint.open(listening: true)
            var info = stat()
            guard lstat(path, &info) == 0 else { throw POSIXError(.ENOENT) }
            file = (path, info)
            socketFiles.record(path, info)
        } else {
            socket = try endpoint.open(listening: true)
            file = nil
        }
    }

    /// A dormant listener consumes a descriptor but no blocked worker thread.
    @MainActor
    func start(accept: @escaping @MainActor (DebugSocket) -> Void,
               failed: @escaping @MainActor (Error) -> Void) throws {
        let unix = file != nil
        let fd = socket.descriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw socketError() }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard self?.source != nil else { return }
            let clientFD = Darwin.accept(fd, nil, nil)
            if clientFD < 0 {
                switch errno {
                case EAGAIN, EINTR, ECONNABORTED: return
                default:
                    let error = socketError()
                    self?.stop()
                    failed(error)
                    return
                }
            }
            do {
                let client = try DebugSocket(owning: clientFD)
                if unix {
                    var uid: uid_t = 0, gid: gid_t = 0
                    guard getpeereid(clientFD, &uid, &gid) == 0, uid == getuid() else { return }
                }
                accept(client)
            } catch { failed(error) }
        }
        // Keep the descriptor alive until dispatch has unregistered the source.
        source.setCancelHandler { [socket] in withExtendedLifetime(socket) {} }
        self.source = source
        source.activate()
    }

    func stop() {
        source?.cancel()
        source = nil
        removeSocketFile()
    }

    deinit { stop() }

    func removeSocketFile() {
        guard let (path, original) = file else { return }
        file = nil
        var info = stat()
        if lstat(path, &info) == 0, info.st_dev == original.st_dev, info.st_ino == original.st_ino {
            unlink(path)
            socketFiles.forget(path)
        }
    }
}

struct TunnelError: LocalizedError {
    let errorDescription: String?
    init(_ description: String) { errorDescription = description }
}

extension TunnelEndpoint {
    /// Whether something on this machine already has the address, so that a listener can't be started there.
    public func isOccupied() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: occupied) }
        }
    }

    /// Binding alone doesn't answer this for a loopback port. A listener has to be able to bind again while connections
    /// from its previous run are still closing, and the option that allows it also lets the listener bind in front of a
    /// service that's listening on every address, silently taking the connections apps make to that service on loopback.
    private var occupied: Bool {
        switch self {
        case .unix(let path):
            var info = stat()
            return lstat(path, &info) == 0
        case .tcp, .tcp6:
            do {
                _ = try open(listening: false, connectTimeout: 250)
                return true
            } catch let error as POSIXError {
                // A service too busy to accept the connection in time is still a service.
                return error.code == .ETIMEDOUT
            } catch {
                return false
            }
        }
    }

    func open(listening: Bool, connectTimeout: Int32 = 5000) throws -> DebugSocket {
        guard isValid else { throw TunnelError("Invalid tunnel endpoint.") }
        switch self {
        case .unix(let path) where listening:
            let url = URL(fileURLWithPath: path)
            try prepareUnixListenerDirectory(url.deletingLastPathComponent())
            return try DebugSocket.unix(url, listening: true)
        case .unix(let path):
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            withUnsafeMutableBytes(of: &address.sun_path) {
                $0.copyBytes(from: path.utf8)
            }
            return try openSocket(&address, family: AF_UNIX, listening: false, connectTimeout: connectTimeout)
        case .tcp(let port):
            guard !listening || !occupied else { throw POSIXError(.EADDRINUSE) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
            return try openSocket(&address, family: AF_INET, listening: listening, connectTimeout: connectTimeout)
        case .tcp6(let port):
            guard !listening || !occupied else { throw POSIXError(.EADDRINUSE) }
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            address.sin6_addr = in6addr_loopback
            return try openSocket(&address, family: AF_INET6, listening: listening, connectTimeout: connectTimeout)
        }
    }

    private func openSocket<Address>(_ address: inout Address, family: Int32, listening: Bool, connectTimeout: Int32) throws -> DebugSocket {
        let stream = try DebugSocket(owning: socket(family, SOCK_STREAM, 0))
        let fd = stream.descriptor
        let length = socklen_t(MemoryLayout<Address>.size)
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                if listening {
                    // Only safe because the caller has checked that nothing answers at this address.
                    var yes: Int32 = 1
                    guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0,
                          bind(fd, address, length) == 0, listen(fd, 32) == 0 else { throw socketError() }
                } else {
                    let flags = fcntl(fd, F_GETFL)
                    guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw socketError() }
                    if Darwin.connect(fd, address, length) < 0 {
                        guard errno == EINPROGRESS else { throw socketError() }
                        var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        let result = poll(&event, 1, connectTimeout)
                        guard result >= 0 else { throw socketError() }
                        guard result > 0 else { throw POSIXError(.ETIMEDOUT) }
                        var failure: Int32 = 0
                        var size = socklen_t(MemoryLayout.size(ofValue: failure))
                        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &size) == 0 else { throw socketError() }
                        guard failure == 0 else { throw socketError(failure) }
                    }
                    guard fcntl(fd, F_SETFL, flags) == 0 else { throw socketError() }
                }
            }
        }
        return stream
    }

    func connectSocket() async throws -> DebugSocket {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try open(listening: false) })
            }
        }
    }
}

private func prepareUnixListenerDirectory(_ directory: URL) throws {
    let unsafeDirectory = TunnelError("Choose a socket in a directory owned by your account and writable only by you.")
    var missing = [URL]()
    var ancestor = directory
    var info = stat()
    while stat(ancestor.path, &info) != 0 {
        guard errno == ENOENT else { throw socketError() }
        missing.append(ancestor)
        ancestor.deleteLastPathComponent()
    }
    guard info.st_mode & S_IFMT == S_IFDIR else { throw POSIXError(.ENOTDIR) }

    if missing.isEmpty {
        guard info.st_uid == getuid(), info.st_mode & 0o022 == 0 else { throw unsafeDirectory }
        return
    }
    // A sticky directory such as /tmp also protects a newly created entry from other users.
    guard info.st_uid == getuid() || info.st_uid == 0,
          info.st_mode & 0o022 == 0 || info.st_mode & S_ISVTX != 0 else { throw unsafeDirectory }
    for component in missing.reversed() {
        if mkdir(component.path, 0o700) != 0 && errno != EEXIST { throw socketError() }
        // Another listener may have just created this directory. Check it before descending.
        guard lstat(component.path, &info) == 0 else { throw socketError() }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              info.st_mode & 0o022 == 0 else { throw unsafeDirectory }
    }
}

func relayTunnel(_ a: DebugSocket, _ b: DebugSocket) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for (source, destination) in [(a, b), (b, a)] {
            group.addTask {
                while true {
                    let bytes = try await source.read(upTo: 65536)
                    if bytes.isEmpty { break }
                    try await destination.write(bytes)
                }
                shutdown(destination.descriptor, SHUT_WR)
            }
        }
        do {
            while try await group.next() != nil { }
        } catch {
            a.stop()
            b.stop()
            throw error
        }
    }
}

private func socketError(_ code: Int32 = errno) -> POSIXError { POSIXError(.init(rawValue: code) ?? .EIO) }
