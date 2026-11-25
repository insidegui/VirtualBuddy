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
