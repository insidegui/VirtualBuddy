import Darwin
import Foundation

/// A connected, blocking byte stream. Independent queues allow debugger interrupts
/// during large replies. shutdown interrupts outstanding calls without reusing the fd.
public final class DebugSocket: @unchecked Sendable {
    public let descriptor: Int32
    private let reader = DispatchQueue(label: "VirtualBuddy.debug.read")
    private let writer = DispatchQueue(label: "VirtualBuddy.debug.write")
    private static var error: Error { POSIXError(.init(rawValue: errno) ?? .EIO) }

    public init(owning descriptor: Int32) throws {
        guard descriptor >= 0 else { throw Self.error }
        self.descriptor = descriptor
        var yes: Int32 = 1
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0 else {
            throw Self.error
        }
    }

    deinit { Darwin.close(descriptor) }
    public func stop() { shutdown(descriptor, SHUT_RDWR) }

    public static var runtime: URL {
        URL(fileURLWithPath: "/private/tmp/vbdebug-\(getuid())", isDirectory: true)
    }

    public static func prepareRuntime() throws {
        if mkdir(runtime.path, 0o700) != 0 && errno != EEXIST { throw error }
        var s = stat()
        guard lstat(runtime.path, &s) == 0, s.st_uid == getuid(), s.st_mode & S_IFMT == S_IFDIR,
              s.st_mode & 0o077 == 0 else { throw VBDebugError("The debugger socket directory must be private to your account.") }
    }

    public static func unix(_ url: URL, listening: Bool) throws -> DebugSocket {
        var address = sockaddr_un()
        let path = url.path.utf8CString
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: path.map { UInt8(bitPattern: $0) }) }
        let stream = try DebugSocket(owning: socket(AF_UNIX, SOCK_STREAM, 0))
        let length = socklen_t(address.sun_len)
        let status = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                listening ? bind(stream.descriptor, $0, length) : connect(stream.descriptor, $0, length)
            }
        }
        guard status == 0 else { throw error }
        if listening {
            guard chmod(url.path, 0o600) == 0, listen(stream.descriptor, 8) == 0 else {
                let failure = error
                unlink(url.path)
                throw failure
            }
        }
        return stream
    }

    static func guestListener() throws -> (DebugSocket, UInt32) {
        let stream = try DebugSocket(owning: socket(AF_VSOCK, SOCK_STREAM, 0))
        var address = sockaddr_vm()
        address.svm_family = sa_family_t(AF_VSOCK)
        address.svm_len = UInt8(MemoryLayout<sockaddr_vm>.size)
        address.svm_port = UInt32(VMADDR_PORT_ANY)
        address.svm_cid = UInt32(VMADDR_CID_ANY)
        var size = socklen_t(address.svm_len)
        let ok = withUnsafeMutablePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(stream.descriptor, $0, size) == 0 && listen(stream.descriptor, 1) == 0 && getsockname(stream.descriptor, $0, &size) == 0
            }
        }
        guard ok else { throw error }
        return (stream, address.svm_port)
    }

    private func io<T>(on queue: DispatchQueue, _ body: @escaping (Int32) throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { result in
                queue.async { result.resume(with: Result { try body(self.descriptor) }) }
            }
        } onCancel: { self.stop() }
    }

    public func accept(timeout: Int32, guest: Bool = false) async throws -> DebugSocket {
        // shutdown on a listening Darwin socket need not wake poll. A second
        // descriptor makes cancelling an unopened debugger rendezvous immediate.
        var wakeup: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &wakeup) == 0 else { throw Self.error }
        let signal = FileHandle(fileDescriptor: wakeup[0], closeOnDealloc: true)
        let receiver = FileHandle(fileDescriptor: wakeup[1], closeOnDealloc: true)
        return try await withTaskCancellationHandler {
            try await io(on: reader) { fd in
                var events = [
                    pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                    pollfd(fd: receiver.fileDescriptor, events: Int16(POLLIN), revents: 0)
                ]
                let count = poll(&events, 2, timeout)
                guard count >= 0 else { throw Self.error }
                guard count > 0 else { throw POSIXError(.ETIMEDOUT) }
                guard events[1].revents == 0 else { throw CancellationError() }
                var address = sockaddr_storage()
                var size = socklen_t(MemoryLayout<sockaddr_storage>.size)
                let socket = try withUnsafeMutablePointer(to: &address) { pointer in
                    try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try DebugSocket(owning: Darwin.accept(fd, $0, &size)) }
                }
                if guest {
                    let host = withUnsafePointer(to: address) { $0.withMemoryRebound(to: sockaddr_vm.self, capacity: 1) {
                        $0.pointee.svm_family == AF_VSOCK && $0.pointee.svm_cid == VMADDR_CID_HOST
                    } }
                    guard host else { throw POSIXError(.EACCES) }
                } else {
                    var uid: uid_t = 0, gid: gid_t = 0
                    guard getpeereid(socket.descriptor, &uid, &gid) == 0, uid == getuid() else { throw POSIXError(.EACCES) }
                }
                return socket
            }
        } onCancel: {
            shutdown(signal.fileDescriptor, SHUT_RDWR)
        }
    }

    public func read(upTo count: Int) async throws -> Data {
        try await io(on: reader) { fd in
            var buffer = Data(count: count)
            let bytes = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            guard bytes >= 0 else { throw Self.error }
            buffer.count = bytes
            return buffer
        }
    }

    public func write(_ data: Data) async throws {
        try await io(on: writer) { fd in
            try data.withUnsafeBytes { bytes in
                var sent = 0
                while sent < bytes.count {
                    let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw Self.error }
                    sent += n
                }
            }
        }
    }

    public func send<T: Encodable>(_ value: T) async throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1 << 20 else { throw POSIXError(.EMSGSIZE) }
        var count = UInt32(data.count).bigEndian
        try await write(withUnsafeBytes(of: &count) { Data($0) } + data)
    }

    public func receive<T: Decodable>(_ type: T.Type) async throws -> T {
        func exactly(_ count: Int) async throws -> Data {
            var data = Data()
            while data.count < count {
                let more = try await read(upTo: count - data.count)
                guard !more.isEmpty else { throw POSIXError(.ECONNRESET) }
                data.append(more)
            }
            return data
        }
        let length = try await exactly(4).withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard length > 0, length <= 1 << 20 else { throw POSIXError(.EMSGSIZE) }
        return try JSONDecoder().decode(type, from: await exactly(length))
    }

    public static func relay(_ a: DebugSocket, _ b: DebugSocket) async {
        await withTaskGroup(of: Void.self) { group in
            for (source, destination) in [(a, b), (b, a)] {
                group.addTask {
                    do {
                        while true {
                            let data = try await source.read(upTo: 65536)
                            if data.isEmpty { break }
                            try await destination.write(data)
                        }
                    } catch { }
                }
            }
            await group.next()
            a.stop()
            b.stop()
            group.cancelAll()
        }
    }
}
