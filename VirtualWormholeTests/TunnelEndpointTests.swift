import Darwin
import Foundation
import Testing
@testable import VirtualWormhole

struct TunnelEndpointTests {
    @Test func validatesSocketPathsAndPortNumbers() {
        for path in ["relative.sock", "/tmp/", "/tmp/bad\u{0}path", "/tmp/\u{202e}socket", "/" + String(repeating: "é", count: 100)] {
            #expect(!TunnelEndpoint.unix(path).isValid)
        }
        #expect(!TunnelEndpoint.tcp(0).isValid)
        #expect(!TunnelEndpoint.tcp6(0).isValid)
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
}
