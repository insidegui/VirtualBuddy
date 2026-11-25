import Foundation
import Testing
@testable import VirtualWormhole

struct ServiceTunnelPolicyTests {
    /// The virtual machine reaches host port 5432 by connecting to its own port 9000.
    private let toHostPort = ServiceTunnel(listensOnHost: false, listener: .tcp(9000), destination: .tcp(5432))
    /// The host reaches guest port 3000 by connecting to its own port 8080.
    private let toGuestPort = ServiceTunnel(listensOnHost: true, listener: .tcp6(8080), destination: .tcp(3000))
    private let toHostSocket = ServiceTunnel(listensOnHost: false, listener: .tcp(9001), destination: .unix("/var/run/virtualbuddy-tests.sock"))
    private let toGuestSocket = ServiceTunnel(listensOnHost: true, listener: .tcp(8081), destination: .unix("/var/run/guest.sock"))

    private var all: [ServiceTunnel] { [toHostPort, toGuestPort, toHostSocket, toGuestSocket] }

    private func permitted(_ configure: (inout ServiceTunnelPolicy) -> Void) -> [ServiceTunnel] {
        var policy = ServiceTunnelPolicy()
        configure(&policy)
        return all.filter(policy.permits)
    }

    @Test func nothingIsRestrictedWithoutAPolicy() {
        #expect(ServiceTunnelPolicy.unrestricted == ServiceTunnelPolicy())
        #expect(permitted { _ in } == all)
        #expect(permitted { $0.requestsDisabled = true } == all)
    }

    @Test func eachSwitchRestrictsOnlyItsPartOfTheFeature() {
        #expect(permitted { $0.tunnelsDisabled = true }.isEmpty)
        #expect(permitted { $0.hostServicesDisabled = true } == [toGuestPort, toGuestSocket])
        #expect(permitted { $0.guestServicesDisabled = true } == [toHostPort, toHostSocket])
        #expect(permitted { $0.unixSocketsDisabled = true } == [toHostPort, toGuestPort])
        #expect(permitted { $0.tcpPortsDisabled = true }.isEmpty)

        var policy = ServiceTunnelPolicy()
        policy.tcpPortsDisabled = true
        let betweenSockets = ServiceTunnel(listensOnHost: false, listener: .unix("/tmp/guest.sock"), destination: .unix("/tmp/host.sock"))
        #expect(policy.permits(betweenSockets))
        #expect(policy.restriction(on: toHostPort) == .tcpPorts)

        policy = ServiceTunnelPolicy()
        policy.tunnelsDisabled = true
        policy.unixSocketsDisabled = true
        #expect(policy.restriction(on: toHostSocket) == .tunnels)
    }

    @Test func portListsApplyToTheHostSideOfATunnel() {
        /// Guest ports 9000 and 3000 are in neither list and don't matter.
        #expect(permitted { $0.setHostPorts(allowed: ["5432"], denied: []) } == [toHostPort, toHostSocket])
        #expect(permitted { $0.setHostPorts(allowed: ["8000-8100"], denied: []) } == [toGuestPort, toHostSocket, toGuestSocket])
        #expect(permitted { $0.setHostPorts(allowed: ["8000-8100"], denied: ["8080"]) } == [toHostSocket, toGuestSocket])
        #expect(permitted { $0.setHostPorts(allowed: nil, denied: ["5000-6000", "8081"]) } == [toGuestPort, toHostSocket])
        #expect(permitted { $0.setHostPorts(allowed: [], denied: []) } == [toHostSocket])
        #expect(permitted { $0.setHostPorts(allowed: [" 5432 ", "8080 - 8081"], denied: []) } == all)

        var policy = ServiceTunnelPolicy()
        policy.setHostPorts(allowed: nil, denied: ["5432"])
        #expect(policy.restriction(on: toHostPort) == .hostPort(5432))
    }

    @Test(arguments: ["", "http", "0", "65536", "-1", "9000-8000", "1-2-3", "8080,8081", "0-10"])
    func portEntriesThatCannotBeUnderstoodNeverPermitMore(entry: String) {
        #expect(ServiceTunnelPolicy.portRange(entry) == nil)
        #expect(permitted { $0.setHostPorts(allowed: [entry], denied: []) } == [toHostSocket])
        #expect(permitted { $0.setHostPorts(allowed: nil, denied: [entry]) } == [toHostSocket])
    }

    @Test func socketPathListsApplyToTheHostSideOfATunnel() {
        /// The guest's /var/run/guest.sock is in neither list and doesn't matter.
        #expect(permitted { $0.setHostSocketPaths(allowed: ["/var/run/virtualbuddy-tests.sock"], denied: []) } == all)
        #expect(permitted { $0.setHostSocketPaths(allowed: ["/var/run/"], denied: []) } == all)
        #expect(permitted { $0.setHostSocketPaths(allowed: ["/var/run"], denied: []) } == [toHostPort, toGuestPort, toGuestSocket])
        #expect(permitted { $0.setHostSocketPaths(allowed: ["/var/run/virtualbuddy-tests"], denied: []) } == [toHostPort, toGuestPort, toGuestSocket])
        #expect(permitted { $0.setHostSocketPaths(allowed: ["/var/run/"], denied: ["/var/run/virtualbuddy-tests.sock"]) } == [toHostPort, toGuestPort, toGuestSocket])
        #expect(permitted { $0.setHostSocketPaths(allowed: nil, denied: ["/var/"]) } == [toHostPort, toGuestPort, toGuestSocket])
        #expect(permitted { $0.setHostSocketPaths(allowed: nil, denied: ["/"]) } == [toHostPort, toGuestPort, toGuestSocket])
        #expect(permitted { $0.setHostSocketPaths(allowed: [], denied: []) } == [toHostPort, toGuestPort, toGuestSocket])
        #expect(permitted { $0.setHostSocketPaths(allowed: ["relative/path", ""], denied: []) } == [toHostPort, toGuestPort, toGuestSocket])
        #expect(permitted { $0.setHostSocketPaths(allowed: nil, denied: ["relative/path"]) } == [toHostPort, toGuestPort, toGuestSocket])

        var policy = ServiceTunnelPolicy()
        policy.setHostSocketPaths(allowed: nil, denied: ["/var/run/virtualbuddy-tests.sock"])
        #expect(policy.restriction(on: toHostSocket) == .hostSocketPath("/var/run/virtualbuddy-tests.sock"))
        let listening = ServiceTunnel(listensOnHost: true, listener: .unix("/var/run/virtualbuddy-tests.sock"), destination: .tcp(2375))
        #expect(!policy.permits(listening))
    }

    @Test func socketPathsAreComparedByTheLocationTheyLeadTo() throws {
        func tunnel(to path: String) -> ServiceTunnel {
            ServiceTunnel(listensOnHost: false, listener: .tcp(9000), destination: .unix(path))
        }
        var policy = ServiceTunnelPolicy()

        /// /tmp is a link to /private/tmp.
        policy.setHostSocketPaths(allowed: nil, denied: ["/private/tmp/"])
        #expect(!policy.permits(tunnel(to: "/tmp/agent.sock")))
        #expect(!policy.permits(tunnel(to: "/tmp/not/created/yet/agent.sock")))
        policy.setHostSocketPaths(allowed: ["/tmp/"], denied: [])
        #expect(policy.permits(tunnel(to: "/private/tmp/agent.sock")))
        #expect(!policy.permits(tunnel(to: "/private/var/agent.sock")))

        let directory = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("secrets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("innocent").path, withDestinationPath: directory.appendingPathComponent("secrets").path)
        policy.setHostSocketPaths(allowed: nil, denied: [directory.appendingPathComponent("secrets").path + "/"])
        #expect(!policy.permits(tunnel(to: directory.appendingPathComponent("innocent/agent.sock").path)))
        #expect(policy.permits(tunnel(to: directory.appendingPathComponent("other/agent.sock").path)))
    }

    @Test func tildeStandsForTheHomeFolder() {
        func tunnel(to path: String) -> ServiceTunnel {
            ServiceTunnel(listensOnHost: false, listener: .tcp(9000), destination: .unix(path))
        }
        var policy = ServiceTunnelPolicy()
        policy.setHostSocketPaths(allowed: ["~/Library/Sockets/"], denied: ["~/Library/Sockets/private.sock"], home: "/Users/someone")
        #expect(policy.permits(tunnel(to: "/Users/someone/Library/Sockets/agent.sock")))
        #expect(!policy.permits(tunnel(to: "/Users/someone/Library/Sockets/private.sock")))
        #expect(!policy.permits(tunnel(to: "/Users/another/Library/Sockets/agent.sock")))
        #expect(!policy.permits(tunnel(to: "/Users/someone/Library/agent.sock")))

        policy.setHostSocketPaths(allowed: nil, denied: ["~"], home: "/Users/someone")
        #expect(policy.permits(tunnel(to: "/Users/someone/agent.sock")))
        policy.setHostSocketPaths(allowed: nil, denied: ["~/"], home: "/Users/someone")
        #expect(!policy.permits(tunnel(to: "/Users/someone/agent.sock")))
    }
}
