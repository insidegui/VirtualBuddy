import Darwin
import Foundation
import Testing
@testable import VirtualWormhole

struct TunnelEndpointTests {
    @Test func validatesSocketPathsAndPortNumbers() {
        for path in ["relative.sock", "/tmp/", "/tmp/bad\u{0}path", "/tmp/\u{202e}socket", "/" + String(repeating: "é", count: 100)] {
            #expect(!TunnelEndpoint.unix(path).isValid)
        }
        for path in ["/tmp/service.sock", "/Users/me/Library/Application Support/App/agent.sock", "/tmp/café/service.sock", "/tmp/.hidden/..sock"] {
            #expect(TunnelEndpoint.unix(path).isValid)
        }
        #expect(!TunnelEndpoint.tcp(0).isValid)
        #expect(!TunnelEndpoint.tcp6(0).isValid)
    }

    @Test(arguments: [
        "/", "/tmp//service.sock", "/tmp/./service.sock", "/tmp/../service.sock", "/Users/me/Public/../Library/agent.sock", "/tmp/..",
        "/tmp/a\u{2028}b.sock", "/tmp/a\u{2029}b.sock", "/tmp/a\u{a0}b.sock", "/tmp/a\u{3000}b.sock", "/tmp/a\u{200b}b.sock",
        "/tmp/a\u{feff}b.sock", "/tmp/a\u{e000}b.sock", "/tmp/a\u{115f}b.sock", "/tmp/a\tb.sock"
    ])
    func rejectsSocketPathsThatDoNotReadAsTheLocationTheyName(path: String) {
        #expect(!TunnelEndpoint.unix(path).isValid)
    }

    @Test func reportsSocketPathsWithCharactersOutsideASCII() {
        #expect(TunnelEndpoint.unix("/tmp/\u{0430}gent.sock").isValid)
        #expect(TunnelEndpoint.unix("/tmp/\u{0430}gent.sock").hasCharactersOutsideASCII)
        #expect(!TunnelEndpoint.unix("/tmp/agent.sock").hasCharactersOutsideASCII)
        #expect(!TunnelEndpoint.tcp(80).hasCharactersOutsideASCII)
    }

    @Test func textFromTheOtherSideIsMadeSafeToDisplay() {
        #expect("Listening".displayableTunnelText == "Listening")
        #expect("Connection to 127.0.0.1:80 failed: Connection refused".displayableTunnelText == "Connection to 127.0.0.1:80 failed: Connection refused")
        #expect("Listening\u{202e}\u{200b}\n\u{2028}now\u{a0}".displayableTunnelText == "Listeningnow")
        #expect(String(repeating: "a", count: 5000).displayableTunnelText.count == 256)
        #expect(String(repeating: "\u{200b}", count: 5000).displayableTunnelText.isEmpty)
    }

    @Test(arguments: [false, true])
    @MainActor func tcpListenerAcceptsOnTheSelectedLoopbackFamily(ipv6: Bool) async throws {
        var endpoint: TunnelEndpoint?
        var listener: TunnelListener?
        for _ in 0..<16 {
            let port = UInt16.random(in: 49152...65535)
            let candidate: TunnelEndpoint = ipv6 ? .tcp6(port) : .tcp(port)
            do {
                listener = try TunnelListener(candidate)
                endpoint = candidate
                break
            } catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        }
        let bound = try #require(listener)
        defer { bound.stop() }
        try bound.start { client in
            Task {
                do { try await client.send("ready") } catch { Issue.record(error) }
            }
        } failed: { Issue.record($0) }
        let address = try #require(endpoint)
        let client = try await address.connectSocket()
        #expect(try await client.receive(String.self, within: .seconds(2)) == "ready")
    }

    /// Listens on every address of the family, the way a development server commonly does.
    private func wildcardListener(ipv6: Bool) throws -> (descriptor: Int32, port: UInt16) {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        var storage = sockaddr_storage()
        var length: socklen_t
        if ipv6 {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_addr = in6addr_any
            length = socklen_t(address.sin6_len)
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: &address) { Array($0) }) }
        } else {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = INADDR_ANY
            length = socklen_t(address.sin_len)
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: &address) { Array($0) }) }
        }
        let port: UInt16 = try withUnsafeMutablePointer(to: &storage) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try #require(bind(fd, $0, length) == 0 && listen(fd, 8) == 0 && getsockname(fd, $0, &length) == 0)
                return $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin_port) }
            }
        }
        return (fd, port)
    }

    @Test(arguments: [false, true])
    func tcpListenerDoesNotStartInFrontOfAServiceListeningOnEveryAddress(ipv6: Bool) async throws {
        let service = try wildcardListener(ipv6: ipv6)
        defer { close(service.descriptor) }
        let endpoint: TunnelEndpoint = ipv6 ? .tcp6(service.port) : .tcp(service.port)

        #expect(await endpoint.isOccupied())
        #expect(throws: POSIXError(.EADDRINUSE)) { try TunnelListener(endpoint) }
    }

    @Test @MainActor func tcpListenerStartsAgainRightAfterItsConnectionsWereClosed() async throws {
        /// The listener's port stays open for as long as the listener exists, so it has to be gone before the port is free.
        func serveOneConnection() async throws -> TunnelEndpoint {
            var bound: (TunnelListener, TunnelEndpoint)?
            for _ in 0..<16 {
                let candidate = TunnelEndpoint.tcp(.random(in: 49152...65535))
                do {
                    bound = (try TunnelListener(candidate), candidate)
                    break
                } catch let error as POSIXError where error.code == .EADDRINUSE { continue }
            }
            let (listener, endpoint) = try #require(bound)
            #expect(await endpoint.isOccupied())

            /// The listening side closes first, which leaves its end of the connection lingering on the port.
            try listener.start { client in
                client.stop()
            } failed: { Issue.record($0) }
            let client = try await endpoint.connectSocket()
            #expect(try await client.read(upTo: 1).isEmpty)
            listener.stop()
            return endpoint
        }

        let endpoint = try await serveOneConnection()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await !endpoint.isOccupied())
        let restarted = try TunnelListener(endpoint)
        restarted.stop()
    }

    @Test @MainActor func stoppedListenerReportsWhenItsAddressIsFree() async throws {
        var bound: (TunnelListener, TunnelEndpoint)?
        for _ in 0..<16 {
            let candidate = TunnelEndpoint.tcp(.random(in: 49152...65535))
            do {
                bound = (try TunnelListener(candidate), candidate)
                break
            } catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        }
        let (listener, endpoint) = try #require(bound)
        try listener.start { _ in } failed: { Issue.record($0) }

        await withCheckedContinuation { continuation in
            listener.stop { continuation.resume() }
        }
        #expect(listener.socket == nil)
        let restarted = try TunnelListener(endpoint)

        /// A listener that never started has nothing to wait for, and still reports.
        await withCheckedContinuation { continuation in
            restarted.stop { continuation.resume() }
        }
        #expect(await !endpoint.isOccupied())
    }

    @Test func unixListenerPathIsOccupiedByAnyExistingFile() async throws {
        let path = "/tmp/\(UUID().uuidString)"
        #expect(await !TunnelEndpoint.unix(path).isOccupied())
        try Data().write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(await TunnelEndpoint.unix(path).isOccupied())
    }

    /// Leaves a socket file with nothing listening on it, as when the app that created it was killed.
    private func abandonSocket(at path: String) throws -> stat {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try #require(bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0)
            }
        }
        var info = stat()
        try #require(lstat(path, &info) == 0)
        return info
    }

    @Test func unixListenerReplacesOnlyAnAbandonedSocketItCreated() async throws {
        let suite = "TunnelEndpointTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let files = TunnelSocketFiles(defaults: defaults)
        let directory = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        try #require(mkdir(directory.path, 0o700) == 0)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("service.sock").path
        let endpoint = TunnelEndpoint.unix(path)

        /// A socket that something else left behind stays where it is.
        let foreign = try abandonSocket(at: path)
        #expect(throws: POSIXError(.EADDRINUSE)) { try TunnelListener(endpoint, socketFiles: files) }
        var info = stat()
        try #require(lstat(path, &info) == 0)
        #expect(info.st_ino == foreign.st_ino)

        /// So does one at a path a listener used before, if it isn't the file that listener created.
        files.record(path, foreign)
        try FileManager.default.removeItem(atPath: path)
        let replacement = try abandonSocket(at: path)
        if replacement.st_ino != foreign.st_ino {
            #expect(throws: POSIXError(.EADDRINUSE)) { try TunnelListener(endpoint, socketFiles: files) }
        }

        /// The socket a listener created and never got to remove is replaced.
        files.record(path, replacement)
        let listener = try TunnelListener(endpoint, socketFiles: files)
        try #require(lstat(path, &info) == 0)
        /// Only a socket created by a listener is private to the account.
        #expect(replacement.st_mode & 0o777 != 0o600)
        #expect(info.st_mode & 0o777 == 0o600)
        _ = try await endpoint.connectSocket()

        /// A recorded socket that's still being served is left alone.
        #expect(throws: POSIXError(.EADDRINUSE)) { try TunnelListener(endpoint, socketFiles: files) }
        _ = try await endpoint.connectSocket()

        listener.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect((defaults.dictionary(forKey: "ServiceTunnelSocketFiles") ?? [:]).isEmpty)
    }

    @Test func unixListenerCreatesPrivateDirectoriesAndRemovesOnlyItsSocket() async throws {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("nested")
        let path = directory.appendingPathComponent("service.sock").path
        let endpoint = TunnelEndpoint.unix(path)

        await #expect(throws: POSIXError.self) { try await endpoint.connectSocket() }
        #expect(!FileManager.default.fileExists(atPath: root.path))

        let listener = try TunnelListener(endpoint)
        for url in [root, directory] {
            var info = stat()
            try #require(lstat(url.path, &info) == 0)
            #expect(info.st_mode & S_IFMT == S_IFDIR)
            #expect(info.st_mode & 0o777 == 0o700)
        }
        var info = stat()
        try #require(lstat(path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)
        _ = try await endpoint.connectSocket()
        listener.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func socketPathIsTrustedOnlyWhenEveryComponentHasATrustedOwner() throws {
        let directory = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        try #require(mkdir(directory.path, 0o700) == 0)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        defer { try? FileManager.default.removeItem(at: link) }

        for path in [directory.path, directory.appendingPathComponent("not/created/yet").path, link.appendingPathComponent("nested").path] {
            try requireTrustedSocketPath(path)
            #expect(throws: TunnelError.self) { try requireTrustedSocketPath(path) { $0 == 0 } }
            #expect(throws: TunnelError.self) { try requireTrustedSocketPath(path) { $0 == getuid() } }
        }
        try requireTrustedSocketPath("/usr/bin") { $0 == 0 }
        #expect(throws: TunnelError.self) { try requireTrustedSocketPath("/usr/bin") { _ in false } }
    }

    @Test func unixListenerPreservesExistingDirectoryPermissions() throws {
        let directory = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        try #require(mkdir(directory.path, 0o700) == 0)
        defer { try? FileManager.default.removeItem(at: directory) }
        let endpoint = TunnelEndpoint.unix(directory.appendingPathComponent("service.sock").path)

        try #require(chmod(directory.path, 0o755) == 0)
        let listener = try TunnelListener(endpoint)
        listener.stop()
        var info = stat()
        try #require(stat(directory.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o755)

        try #require(chmod(directory.path, 0o777) == 0)
        #expect(throws: TunnelError.self) { try TunnelListener(endpoint) }
        let nested = directory.appendingPathComponent("nested")
        #expect(throws: TunnelError.self) { try TunnelListener(.unix(nested.appendingPathComponent("service.sock").path)) }
        #expect(!FileManager.default.fileExists(atPath: nested.path))
        try #require(stat(directory.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o777)
    }
}
