import Darwin
import Foundation
import MacDebugProtocol

/// Owns the listening socket and its filesystem entry for exactly one rule.
final class TunnelListener {
    let socket: DebugSocket
    private var source: DispatchSourceRead?
    private var file: (String, stat)?

    init(_ endpoint: TunnelEndpoint) throws {
        socket = try endpoint.open(listening: true)
        if case .unix(let path) = endpoint {
            var info = stat()
            guard lstat(path, &info) == 0 else { throw POSIXError(.ENOENT) }
            file = (path, info)
        } else {
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
        }
    }
}

struct TunnelError: LocalizedError {
    let errorDescription: String?
    init(_ description: String) { errorDescription = description }
}

extension TunnelEndpoint {
    func open(listening: Bool) throws -> DebugSocket {
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
            return try openSocket(&address, family: AF_UNIX, listening: false)
        case .tcp(let port):
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
            return try openSocket(&address, family: AF_INET, listening: listening)
        case .tcp6(let port):
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            address.sin6_addr = in6addr_loopback
            return try openSocket(&address, family: AF_INET6, listening: listening)
        }
    }

    private func openSocket<Address>(_ address: inout Address, family: Int32, listening: Bool) throws -> DebugSocket {
        let stream = try DebugSocket(owning: socket(family, SOCK_STREAM, 0))
        let fd = stream.descriptor
        let length = socklen_t(MemoryLayout<Address>.size)
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                if listening {
                    var yes: Int32 = 1
                    guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0,
                          bind(fd, address, length) == 0, listen(fd, 32) == 0 else { throw socketError() }
                } else {
                    let flags = fcntl(fd, F_GETFL)
                    guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw socketError() }
                    if Darwin.connect(fd, address, length) < 0 {
                        guard errno == EINPROGRESS else { throw socketError() }
                        var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        let result = poll(&event, 1, 5000)
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
