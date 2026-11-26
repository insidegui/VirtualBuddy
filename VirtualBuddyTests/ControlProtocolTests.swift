import Foundation
import Testing
import VirtualWormhole
@testable import VirtualBuddy

struct ControlProtocolTests {
    @Test(arguments: [
        ("host:8080", TunnelSide(onHost: true, endpoint: .tcp(8080)), "host:8080"),
        ("guest:80", TunnelSide(onHost: false, endpoint: .tcp(80)), "guest:80"),
        ("HOST:tcp:443", TunnelSide(onHost: true, endpoint: .tcp(443)), "host:443"),
        ("guest:tcp6:8080", TunnelSide(onHost: false, endpoint: .tcp6(8080)), "guest:tcp6:8080"),
        ("host:/tmp/service.sock", TunnelSide(onHost: true, endpoint: .unix("/tmp/service.sock")), "host:/tmp/service.sock"),
    ])
    func tunnelEndsAreWrittenAsASideAndAnAddress(text: String, side: TunnelSide, description: String) {
        #expect(TunnelSide(text) == side)
        #expect(side.description == description)
        #expect(TunnelSide(description) == side)
    }

    @Test(arguments: ["8080", "host", "host:", "host:0", "host:65536", "mac:8080", "guest:udp:53", "host:relative/path", "host:/tmp/../etc/passwd", "host:/tmp/"])
    func invalidTunnelEndsAreRejected(text: String) {
        #expect(TunnelSide(text) == nil)
    }

    @Test func aTunnelConnectsTheTwoSides() throws {
        let host = TunnelSide(onHost: true, endpoint: .tcp(8080))
        let guest = TunnelSide(onHost: false, endpoint: .tcp(80))

        let toGuest = try #require(ServiceTunnel(listen: host, destination: guest))
        #expect(toGuest.listensOnHost)
        #expect(toGuest.listenSide == host)
        #expect(toGuest.destinationSide == guest)

        let toHost = try #require(ServiceTunnel(listen: guest, destination: host))
        #expect(!toHost.listensOnHost)
        #expect(toHost.destinationSide == host)

        #expect(ServiceTunnel(listen: host, destination: host) == nil)
        #expect(ServiceTunnel(listen: guest, destination: guest) == nil)
    }

    @Test func tunnelsAreFoundByWhereTheyListenOrByTheStartOfTheirIdentifier() throws {
        let web = ServiceTunnel(listensOnHost: true, listener: .tcp(8080), destination: .tcp(80))
        let database = ServiceTunnel(listensOnHost: false, listener: .tcp(8080), destination: .tcp(5432))
        let tunnels = [web, database]

        #expect(try ServiceTunnel.resolve("host:8080", in: tunnels) == web)
        #expect(try ServiceTunnel.resolve("guest:8080", in: tunnels) == database)
        #expect(try ServiceTunnel.resolve(String(web.id.uuidString.lowercased().prefix(13)), in: tunnels) == web)
        #expect(try ServiceTunnel.resolve(database.id.uuidString, in: tunnels) == database)

        #expect(throws: ControlError(.notFound, "There's no service tunnel matching \"host:9\".")) { try ServiceTunnel.resolve("host:9", in: tunnels) }
        #expect(code(of: { try ServiceTunnel.resolve("ab", in: tunnels) }) == .notFound)
        #expect(code(of: { try ServiceTunnel.resolve("00000000", in: tunnels) }) == .notFound)

        let twin = ServiceTunnel(listensOnHost: true, listener: .tcp(8080), destination: .tcp(81))
        #expect(code(of: { try ServiceTunnel.resolve("host:8080", in: [web, twin]) }) == .ambiguous)
    }

    private struct Machine: Equatable {
        var name: String
        var uuid = UUID()
        var path: String
    }

    private func resolve(_ reference: String, in machines: [Machine]) throws -> Machine {
        try VMReference.resolve(reference, in: machines, name: \.name, uuid: \.uuid, path: \.path)
    }

    private func code<T>(of body: () throws -> T) -> ControlError.Code? {
        do {
            _ = try body()
            return nil
        } catch {
            return (error as? ControlError)?.code
        }
    }

    @Test func virtualMachinesAreFoundByNameIdentifierOrPath() throws {
        let sequoia = Machine(name: "Sequoia", path: "/Library/VMs/Sequoia.vbvm")
        let copy = Machine(name: "Sequoia Copy", uuid: sequoia.uuid, path: "/Library/VMs/Sequoia Copy.vbvm")
        let ubuntu = Machine(name: "Ubuntu", path: "/Library/VMs/Ubuntu.vbvm")
        let machines = [sequoia, copy, ubuntu]

        #expect(try resolve("sequoia", in: machines) == sequoia)
        #expect(try resolve("Sequoia Copy", in: machines) == copy)
        #expect(try resolve(ubuntu.uuid.uuidString.lowercased(), in: machines) == ubuntu)
        #expect(try resolve("/Library/VMs/../VMs/Ubuntu.vbvm", in: machines) == ubuntu)

        #expect(code(of: { try resolve("Tahoe", in: machines) }) == .notFound)
        #expect(code(of: { try resolve("/Library/VMs/Tahoe.vbvm", in: machines) }) == .notFound)

        // A copy made outside of the app has the identifier of its original, so only the path tells them apart.
        do {
            _ = try resolve(sequoia.uuid.uuidString, in: machines)
            Issue.record("An identifier shared by two virtual machines doesn't refer to either" as Comment)
        } catch let error as ControlError {
            #expect(error.code == .ambiguous)
            #expect(error.message.contains(sequoia.path) && error.message.contains(copy.path))
        }

        // A name that happens to read as an identifier is still a name.
        let named = Machine(name: ubuntu.uuid.uuidString, path: "/Library/VMs/Named.vbvm")
        #expect(try resolve(ubuntu.uuid.uuidString, in: machines + [named]) == named)
    }

    @Test func pathsAreSentToTheAppInFull() {
        #expect(VMReference.normalized("Sequoia", relativeTo: "/Users/me") == "Sequoia")
        #expect(VMReference.normalized("./Sequoia.vbvm", relativeTo: "/Users/me/VMs") == "/Users/me/VMs/Sequoia.vbvm")
        #expect(VMReference.normalized("../Other/Sequoia.vbvm", relativeTo: "/Users/me/VMs") == "/Users/me/Other/Sequoia.vbvm")
        #expect(VMReference.normalized("/Volumes/VMs/Sequoia.vbvm", relativeTo: "/Users/me") == "/Volumes/VMs/Sequoia.vbvm")
        #expect(VMReference.normalized("~/VMs/Sequoia.vbvm", relativeTo: "/") == NSHomeDirectory() + "/VMs/Sequoia.vbvm")
    }

    @Test func everyFailureHasAnExitCodeThatScriptsCanTellApart() {
        let codes = Dictionary(grouping: ControlError.Code.allCases) { ControlError($0, "").exitCode }
        #expect(codes[1] == [.failure])
        #expect(codes[3] == [.accessDisabled, .unreachable, .incompatibleVersion])
        #expect(codes[4] == [.notFound, .ambiguous])
        #expect(codes[5] == [.invalidState])
        #expect(codes[6] == [.guestUnavailable, .unsupported])
        #expect(codes[7] == [.timedOut])
        #expect(codes[8] == [.reviewRequired, .restrictedByOrganization])
        // 0 is success, 2 is taken by shells and 64 by the argument parser.
        #expect(Set(codes.keys).isDisjoint(with: [0, 2, 64]))
    }

    @Test func requestsAndRepliesSurviveTheTripOverTheSocket() throws {
        let listen = TunnelSide(onHost: true, endpoint: .unix("/tmp/service.sock"))
        let destination = TunnelSide(onHost: false, endpoint: .tcp6(8080))
        let request = ControlRequest(command: .tunnelAdd(vm: "Sequoia", listen: listen, destination: destination, wait: true), timeout: 30)
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(request))

        #expect(decoded.version == ControlProtocol.version)
        #expect(decoded.timeout == 30)
        guard case .tunnelAdd("Sequoia", listen, destination, true) = decoded.command else {
            Issue.record("The command changed on the way" as Comment)
            return
        }

        let failure = ControlReply.failure(ControlError(.reviewRequired, "Needs review."))
        guard case .failure(let error) = try JSONDecoder().decode(ControlReply.self, from: JSONEncoder().encode(failure)) else {
            Issue.record("The reply changed on the way" as Comment)
            return
        }
        #expect(error == ControlError(.reviewRequired, "Needs review."))
    }

    @Test func outputKeepsColumnsAlignedWithoutTrailingSpaces() {
        let table = ControlOutput.table(["NAME", "STATE"], [["Sequoia", "running"], ["Ubuntu 24.04", "stopped"]])
        #expect(table == """
        NAME          STATE
        Sequoia       running
        Ubuntu 24.04  stopped
        """)

        let json = ControlOutput.json(ControlError(.notFound, "Nothing there."))
        #expect(json.contains("\"code\" : \"notFound\""))
        #expect(json.contains("\"message\" : \"Nothing there.\""))
    }
}
