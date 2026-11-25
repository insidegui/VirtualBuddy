import Foundation
import Testing
import VMBridge
import os
@testable import VirtualWormhole

@Suite @MainActor
struct GuestSessionTests {
    @Test(arguments: [true, false])
    func serviceTunnelsRequireApprovalAndRelayAfterHalfClose(listensOnHost: Bool) async throws {
        let fixture = await SessionFixture.make()
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }

        // Replace only the physical Virtio hop. Both session engines, the
        // control protocol and all client/service sockets are real.
        let linkAddress = TunnelEndpoint.unix(directory.appendingPathComponent("link").path)
        fixture.guest.tunnels.makeGuestListener = {
            let listener = try TunnelListener(linkAddress)
            return .init(port: 23456) {
                defer { listener.removeSocketFile() }
                let socket = try #require(listener.socket)
                return try await socket.accept(timeout: 5000)
            }
        }
        fixture.host.tunnels.connect = { _ in .init(stream: try await linkAddress.connectSocket(), owner: nil) }

        // Reserve a kernel-selected loopback service port and keep it bound.
        let serviceFD = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(serviceFD) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        var size = socklen_t(address.sin_len)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serviceFD, $0, size) == 0 && listen(serviceFD, 1) == 0 && getsockname(serviceFD, $0, &size) == 0
            }
        }
        try #require(bound)
        let path = directory.appendingPathComponent("client").path
        let rule = ServiceTunnel(listensOnHost: listensOnHost, listener: .unix(path), destination: .tcp(UInt16(bigEndian: address.sin_port)))
        try await fixture.connect()
        try await eventually { fixture.host.tunnels.state.available }
        try await fixture.guest.tunnels.propose(rule)
        try await eventually { fixture.guest.tunnels.state.requests == [rule] }
        #expect(fixture.host.tunnels.state.rules.isEmpty)
        let token = try #require(await fixture.guestConnection.token)
        for action: TunnelControl.Action in [.reverse(rule.id, UUID(), 23456), .open(rule.id, UUID()), .snapshot(42, [rule], [], [:])] {
            let reply = try await fixture.guestConnection.request(TunnelControl(session: token, action: action), reply: TunnelReply.self, timeout: .seconds(1))
            if case .failure = reply {} else { Issue.record("Host accepted an unauthorized tunnel operation") }
        }
        #expect(!FileManager.default.fileExists(atPath: path))
        fixture.host.tunnels.decline(rule.id)
        try await eventually { fixture.guest.tunnels.state.requests.isEmpty }

        try await fixture.guest.tunnels.propose(rule)
        fixture.host.tunnels.approvedRules = { [rule] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.guest.tunnels.state.status[rule.id] == "Listening" }
        let client = try await rule.listener.connectSocket()
        try await client.send("request")
        shutdown(client.descriptor, SHUT_WR)
        let response = Task.detached {
            var pending = pollfd(fd: serviceFD, events: Int16(POLLIN), revents: 0)
            guard poll(&pending, 1, 5000) == 1 else { throw TestFailure.deadline }
            let fd = accept(serviceFD, nil, nil)
            defer { close(fd) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
            var bytes = [UInt8](repeating: 0, count: 128)
            var data = Data()
            while true {
                let n = read(fd, &bytes, bytes.count)
                guard n >= 0 else { throw TestFailure.deadline }
                if n == 0 { break }
                data.append(contentsOf: bytes.prefix(n))
            }
            return data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
        #expect(try await client.receive(String.self, within: .seconds(8)) == "request")
        #expect(try await response.value > 0)

        // Turning off an approved rule also closes an already connected, idle client.
        let idle = try await rule.listener.connectSocket()
        let idleServiceFD = try await Task.detached {
            var event = pollfd(fd: serviceFD, events: Int16(POLLIN), revents: 0)
            guard poll(&event, 1, 5000) == 1 else { throw TestFailure.deadline }
            return accept(serviceFD, nil, nil)
        }.value
        defer { close(idleServiceFD) }
        var disabled = rule
        disabled.isEnabled = false
        fixture.host.tunnels.approvedRules = { [disabled] in [disabled] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.guest.tunnels.state.rules == [disabled] }
        do {
            _ = try await idle.receive(String.self, within: .seconds(2))
            Issue.record("An idle client stayed connected after revocation")
        } catch let error as POSIXError {
            #expect(error.code == .ECONNRESET)
        }
        fixture.host.tunnels.approvedRules = { [] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { !FileManager.default.fileExists(atPath: path) && fixture.guest.tunnels.state.rules.isEmpty }
        await fixture.stop()
    }

    @Test func tunnelReplacingAnotherAtTheSameAddressStartsListening() async throws {
        let fixture = await SessionFixture.make()
        let listener = TunnelEndpoint.tcp(.random(in: 49152...65535))
        let original = ServiceTunnel(listensOnHost: true, listener: listener, destination: .tcp(3000))
        let replacement = ServiceTunnel(listensOnHost: true, listener: listener, destination: .tcp(3001))
        fixture.host.tunnels.approvedRules = { [original] }
        try await fixture.connect()
        try await eventually { fixture.host.tunnels.state.status[original.id] != nil }
        try #require(fixture.host.tunnels.state.status[original.id] == "Listening")

        fixture.host.tunnels.approvedRules = { [replacement] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.host.tunnels.state.status[replacement.id] != nil }
        #expect(fixture.host.tunnels.state.status[replacement.id] == "Listening")
        #expect(await listener.isOccupied())

        fixture.host.tunnels.approvedRules = { [] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.host.tunnels.state.rules.isEmpty }
        await fixture.stop()
    }

    @Test func statusReportedByTheGuestIsMadeSafeToDisplayOnTheHost() async throws {
        let fixture = await SessionFixture.make()
        let rule = ServiceTunnel(listensOnHost: false, listener: .tcp(.random(in: 49152...65535)), destination: .tcp(3000))
        fixture.host.tunnels.approvedRules = { [rule] }
        try await fixture.connect()
        try await eventually { fixture.host.tunnels.state.status[rule.id] != nil }

        let token = try #require(await fixture.guestConnection.token)
        let text = "Click Allow\u{202e}\n\u{2028}" + String(repeating: "!", count: 2000)
        let reply = try await fixture.guestConnection.request(TunnelControl(session: token, action: .status(rule.id, text)), reply: TunnelReply.self, timeout: .seconds(1))
        if case .ok = reply {} else { Issue.record("Host rejected a status for a tunnel the guest listens for") }
        #expect(fixture.host.tunnels.state.status[rule.id] == "Click Allow" + String(repeating: "!", count: 245))

        fixture.host.tunnels.approvedRules = { [] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.guest.tunnels.state.rules.isEmpty }
        await fixture.stop()
    }

    @Test func oneTunnelCannotUseEveryConnectionOfTheVirtualMachine() async throws {
        let fixture = await SessionFixture.make()
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let linkAddress = TunnelEndpoint.unix(directory.appendingPathComponent("link").path)
        fixture.guest.tunnels.makeGuestListener = {
            let listener = try TunnelListener(linkAddress)
            return .init(port: 23456) {
                defer { listener.removeSocketFile() }
                let socket = try #require(listener.socket)
                return try await socket.accept(timeout: 5000)
            }
        }
        fixture.host.tunnels.connect = { _ in .init(stream: try await linkAddress.connectSocket(), owner: nil) }
        fixture.host.tunnels.ruleConnectionLimit = 1

        /// Connections to the service stay open without it doing anything.
        let service = try TunnelListener(.unix(directory.appendingPathComponent("service").path))
        defer { service.stop() }
        let limited = ServiceTunnel(listensOnHost: true, listener: .unix(directory.appendingPathComponent("limited").path), destination: .unix(directory.appendingPathComponent("service").path))
        let other = ServiceTunnel(listensOnHost: true, listener: .unix(directory.appendingPathComponent("other").path), destination: .unix(directory.appendingPathComponent("service").path))
        fixture.host.tunnels.approvedRules = { [limited, other] }
        try await fixture.connect()
        try await eventually {
            fixture.host.tunnels.state.status[limited.id] == "Listening" && fixture.host.tunnels.state.status[other.id] == "Listening"
        }

        let first = try await limited.listener.connectSocket()
        try await Task.sleep(for: .milliseconds(200))
        let refused = try await limited.listener.connectSocket()
        #expect(try await refused.read(upTo: 1).isEmpty)
        try await eventually { fixture.host.tunnels.state.status[limited.id] == "This tunnel has reached its connection limit." }

        /// The other tunnel still has its share.
        let unaffected = try await other.listener.connectSocket()
        try await Task.sleep(for: .milliseconds(200))
        #expect(fixture.host.tunnels.state.status[other.id] == "Listening")

        withExtendedLifetime((first, unaffected)) {}
        fixture.host.tunnels.approvedRules = { [] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.guest.tunnels.state.rules.isEmpty }
        await fixture.stop()
    }

    @Test func guestIsNotToldWhyATunnelFailedOnTheHost() async throws {
        let fixture = await SessionFixture.make()
        /// Can't be created, for a reason that describes a folder on the host.
        let rule = ServiceTunnel(listensOnHost: true, listener: .unix("/usr/bin/\(UUID().uuidString).sock"), destination: .tcp(3000))
        fixture.host.tunnels.approvedRules = { [rule] }
        try await fixture.connect()
        try await eventually { fixture.guest.tunnels.state.status[rule.id] != nil }

        let reason = try #require(fixture.host.tunnels.state.status[rule.id])
        #expect(reason != "Listening" && reason != "Not available on the host")
        #expect(fixture.guest.tunnels.state.status[rule.id] == "Not available on the host")

        /// The guest keeps being told the same after asking for everything again.
        fixture.host.tunnels.reloadConfiguration()
        try await Task.sleep(for: .milliseconds(200))
        #expect(fixture.guest.tunnels.state.status[rule.id] == "Not available on the host")
        await fixture.stop()
    }

    @Test func organizationPolicyDecidesWhichApprovedTunnelsRunAndWhatCanBeRequested() async throws {
        let fixture = await SessionFixture.make()
        let betweenPorts = ServiceTunnel(listensOnHost: true, listener: .tcp(.random(in: 49152...65535)), destination: .tcp(3000))
        let toGuestSocket = ServiceTunnel(listensOnHost: true, listener: .tcp(.random(in: 49152...65535)), destination: .unix("/tmp/guest.sock"))
        var policy = ServiceTunnelPolicy()
        policy.unixSocketsDisabled = true
        fixture.host.tunnels.approvedRules = { [betweenPorts, toGuestSocket] }
        fixture.host.tunnels.policy = { policy }
        try await fixture.connect()
        try await eventually { fixture.host.tunnels.state.status[betweenPorts.id] == "Listening" }
        #expect(fixture.host.tunnels.state.rules == [betweenPorts])
        #expect(await !toGuestSocket.listener.isOccupied())

        /// The guest can't get by asking what the policy doesn't allow, and isn't told what the policy is.
        let refused = ServiceTunnel(listensOnHost: false, listener: .tcp(9000), destination: .unix("/var/run/docker.sock"))
        await #expect(throws: TunnelError.self) { try await fixture.guest.tunnels.propose(refused) }
        #expect(fixture.host.tunnels.state.requests.isEmpty)
        let allowed = ServiceTunnel(listensOnHost: false, listener: .tcp(9000), destination: .tcp(5432))
        try await fixture.guest.tunnels.propose(allowed)
        try await eventually { fixture.host.tunnels.state.requests == [allowed] }

        /// A stricter policy takes effect on tunnels that are running and on requests that are waiting.
        policy.tunnelsDisabled = true
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.guest.tunnels.state.rules.isEmpty && fixture.guest.tunnels.state.requests.isEmpty }
        try await eventually { await !betweenPorts.listener.isOccupied() }

        /// Without the policy, everything the user approved runs again.
        policy = .unrestricted
        fixture.host.tunnels.reloadConfiguration()
        try await eventually {
            fixture.host.tunnels.state.status[betweenPorts.id] == "Listening" && fixture.host.tunnels.state.status[toGuestSocket.id] == "Listening"
        }

        policy.requestsDisabled = true
        await #expect(throws: TunnelError.self) { try await fixture.guest.tunnels.propose(allowed) }
        #expect(fixture.host.tunnels.state.rules.count == 2)

        fixture.host.tunnels.approvedRules = { [] }
        fixture.host.tunnels.reloadConfiguration()
        try await eventually { fixture.guest.tunnels.state.rules.isEmpty }
        await fixture.stop()
    }

    @Test func reconnectReloadsHostApprovalBeforePublishingMappings() async throws {
        let fixture = await SessionFixture.make()
        var disabled = ServiceTunnel(listensOnHost: true, listener: .tcp(8000), destination: .tcp(80))
        disabled.isEnabled = false
        var verified = [disabled]
        var loads = 0
        fixture.host.tunnels.approvedRules = {
            loads += 1
            return verified
        }
        try await fixture.connect()
        try await eventually { fixture.guest.tunnels.state.rules == verified }
        await fixture.disconnect()
        try await eventually { !fixture.host.tunnels.state.available && !fixture.guest.tunnels.state.available }
        verified = []
        await fixture.hostConnection.transition(.connected)
        await fixture.guestConnection.transition(.connected)
        try await eventually { fixture.host.tunnels.state.available && loads == 2 }
        #expect(fixture.host.tunnels.state.rules.isEmpty)
        await fixture.stop()
    }

    @Test func debuggingRequiresTheConnectedGuestsOwnCapability() async throws {
        let first = await SessionFixture.make()
        let second = await SessionFixture.make()
        try await first.connect()
        try await second.connect()
        #expect(first.host.debugging.available && second.host.debugging.available)
        #expect(first.host.debugging.supportsProvisioning && second.host.debugging.supportsProvisioning)
        let previousGuest = InitializeGuest(session: UUID(), capabilities: [DebugGuestService.capability])
        _ = try await first.guestConnection.request(previousGuest, reply: InitializeGuestReply.self, timeout: .seconds(1))
        #expect(first.host.debugging.available && !first.host.debugging.supportsProvisioning)
        #expect(second.host.debugging.supportsProvisioning)
        _ = try await first.guestConnection.request(InitializeGuest(session: UUID()), reply: InitializeGuestReply.self, timeout: .seconds(1))
        #expect(!first.host.debugging.available)
        #expect(second.host.debugging.available)
        await second.disconnect()
        try await eventually { !second.host.debugging.available && !second.host.debugging.supportsProvisioning }
        await first.stop()
        await second.stop()
    }

    @Test func appearanceIsManualByDefaultAndNeverChangesTheHost() async throws {
        let fixture = await SessionFixture.make()
        fixture.hostFeatures.isDarkModeEnabled = true
        try await fixture.connect()
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled == false }
        #expect(!fixture.host.appearance.automaticallySync)
        #expect(fixture.guestFeatures.appliedAppearances.isEmpty)

        fixture.host.appearance.setDarkModeEnabled(true)
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled == true && !fixture.host.appearance.state.isUpdating }
        #expect(fixture.guestFeatures.appliedAppearances == [true])

        fixture.guestFeatures.isDarkModeEnabled = false
        fixture.guestFeatures.postAppearanceChange?()
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled == false }
        #expect(fixture.hostFeatures.isDarkModeEnabled)
        #expect(fixture.hostFeatures.appliedAppearances.isEmpty)
        await fixture.stop()
    }

    @Test func appearanceSyncAppliesImmediatelyTracksHostAndSurvivesReconnect() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled != nil }
        fixture.hostFeatures.isDarkModeEnabled = true
        fixture.host.appearance.automaticallySync = true
        try await eventually { fixture.guestFeatures.isDarkModeEnabled && !fixture.host.appearance.state.isUpdating }

        fixture.hostFeatures.isDarkModeEnabled = false
        fixture.hostFeatures.postAppearanceChange?()
        try await eventually { !fixture.guestFeatures.isDarkModeEnabled && !fixture.host.appearance.state.isUpdating }

        fixture.guestFeatures.isDarkModeEnabled = true
        fixture.guestFeatures.postAppearanceChange?()
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled == true }
        #expect(!fixture.hostFeatures.isDarkModeEnabled)
        #expect(fixture.hostFeatures.appliedAppearances.isEmpty)

        await fixture.disconnect()
        try await eventually { !fixture.guest.isConnected && fixture.host.appearance.state.isDarkModeEnabled == nil }
        #expect(fixture.hostFeatures.postAppearanceChange == nil)
        #expect(fixture.guestFeatures.postAppearanceChange == nil)
        await fixture.hostConnection.transition(.connected)
        await fixture.guestConnection.transition(.connected)
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled == false && !fixture.host.appearance.state.isUpdating }
        #expect(!fixture.guestFeatures.isDarkModeEnabled)

        fixture.host.appearance.automaticallySync = false
        let count = fixture.guestFeatures.appliedAppearances.count
        fixture.hostFeatures.isDarkModeEnabled = true
        fixture.hostFeatures.postAppearanceChange?()
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.guestFeatures.appliedAppearances.count == count)
        await fixture.stop()
        #expect(fixture.hostFeatures.appearanceObserverRegistrations == fixture.hostFeatures.appearanceObserverRemovals)
        #expect(fixture.guestFeatures.appearanceObserverRegistrations == fixture.guestFeatures.appearanceObserverRemovals)
    }

    @Test func appearanceRejectsStaleReportsAndCommandsToTheHost() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        let token = try #require(await fixture.guestConnection.token)
        try await fixture.guestConnection.send(GuestAppearanceUpdate(session: token, revision: 20, isDarkModeEnabled: true))
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled == true }
        try await fixture.guestConnection.send(GuestAppearanceUpdate(session: UUID(), revision: 30, isDarkModeEnabled: false))
        try await fixture.guestConnection.send(GuestAppearanceUpdate(session: token, revision: 19, isDarkModeEnabled: false))
        try await fixture.guestConnection.send(GuestAppearanceUpdate(session: token, revision: 20, isDarkModeEnabled: false))
        try await fixture.hostConnection.send(GuestAppearanceUpdate(session: token, revision: 40, isDarkModeEnabled: true))
        for (connection, session) in [(fixture.guestConnection, token), (fixture.hostConnection, UUID())] {
            do {
                _ = try await connection.request(SetGuestAppearance(session: session, isDarkModeEnabled: true), reply: SetGuestAppearanceReply.self, timeout: .milliseconds(50))
                Issue.record("Invalid appearance command was accepted")
            } catch VMBridgeError.requestTimedOut { }
        }
        #expect(fixture.host.appearance.state.isDarkModeEnabled == true)
        #expect(fixture.guest.appearance.state.isDarkModeEnabled == nil)
        #expect(fixture.hostFeatures.appliedAppearances.isEmpty)
        #expect(fixture.guestFeatures.appliedAppearances.isEmpty)
        await fixture.stop()
    }

    @Test func appearanceFailureIsReportedAndCanBeRetried() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled != nil }
        fixture.guestFeatures.appearanceFails = true
        fixture.host.appearance.setDarkModeEnabled(true)
        try await eventually { fixture.host.appearance.state.errorMessage != nil && !fixture.host.appearance.state.isUpdating }
        #expect(fixture.host.appearance.state.isDarkModeEnabled == false)
        fixture.guestFeatures.appearanceFails = false
        fixture.host.appearance.setDarkModeEnabled(true)
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled == true && !fixture.host.appearance.state.isUpdating }
        #expect(fixture.host.appearance.state.errorMessage == nil)
        await fixture.stop()
    }

    @Test func rapidHostAppearanceChangesCoalesceAndDisconnectCancelsPendingCommands() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        try await eventually { fixture.host.appearance.state.isDarkModeEnabled != nil }
        await fixture.hostConnection.delayAppearanceRequests(by: .milliseconds(100))
        fixture.hostFeatures.isDarkModeEnabled = true
        fixture.host.appearance.automaticallySync = true
        try await eventually { await fixture.hostConnection.sentAppearanceRequests == [true] }
        for enabled in [false, true, false] {
            fixture.hostFeatures.isDarkModeEnabled = enabled
            fixture.hostFeatures.postAppearanceChange?()
        }
        try await eventually { !fixture.host.appearance.state.isUpdating }
        #expect(await fixture.hostConnection.sentAppearanceRequests == [true, false])
        #expect(!fixture.guestFeatures.isDarkModeEnabled)

        await fixture.hostConnection.delayAppearanceRequests(by: .seconds(1))
        fixture.hostFeatures.isDarkModeEnabled = true
        fixture.hostFeatures.postAppearanceChange?()
        try await eventually { await fixture.hostConnection.sentAppearanceRequests.count == 3 }
        await fixture.disconnect()
        try await eventually { !fixture.host.isConnected && !fixture.guest.isConnected }
        #expect(fixture.host.appearance.state.isDarkModeEnabled == nil)
        #expect(!fixture.host.appearance.state.isUpdating)
        #expect(!fixture.guestFeatures.isDarkModeEnabled)
        await fixture.stop()
    }

    @Test func appearanceSyncPreferenceIsIndependentForEachGuest() async throws {
        let first = await SessionFixture.make()
        let second = await SessionFixture.make()
        for fixture in [first, second] {
            fixture.hostFeatures.isDarkModeEnabled = true
        }
        first.host.appearance.automaticallySync = true
        try await first.connect()
        try await second.connect()
        try await eventually {
            first.host.appearance.state.isDarkModeEnabled == true &&
            second.host.appearance.state.isDarkModeEnabled == false
        }
        #expect(first.guestFeatures.isDarkModeEnabled)
        #expect(second.guestFeatures.appliedAppearances.isEmpty)
        await first.stop()
        await second.stop()
    }

    @Test func appearanceWaitsForHostCapabilityAndGuestReport() async throws {
        let connection = TestConnection()
        let context = GuestServiceContext(connection: connection, endpoint: .guest, requestTimeout: .seconds(1))
        context.session = UUID()
        context.isConnected = true
        var observed = false
        let guest = AppearanceGuestService(context: context, read: { false }, apply: { _ in
            Issue.record("An older host must not control appearance")
        }, observe: { _ in observed = true; return {} })
        guest.activate(notifications: [])
        #expect(!observed)

        let hostContext = GuestServiceContext(connection: connection, endpoint: .host, requestTimeout: .seconds(1))
        hostContext.session = UUID()
        hostContext.isConnected = true
        let host = AppearanceGuestService(context: hostContext, read: { true }, apply: { _ in
            Issue.record("Host appearance must never be changed")
        }, observe: { _ in return {} })
        host.automaticallySync = true
        host.activate(notifications: [])
        host.setDarkModeEnabled(true)
        #expect(host.state.isDarkModeEnabled == nil)
        #expect(!host.state.isUpdating)
        guest.invalidate()
        host.invalidate()
        await guest.drain()
        await host.drain()
    }

    @Test func systemInformationRefreshesOnEventsAndReconnect() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        #expect(fixture.hostFeatures.systemReports.last?.osVersion == "26.0")
        fixture.guestFeatures.systemInformation.osBuild = "updated-build"
        fixture.guestFeatures.postSystemChange?()
        try await eventually { fixture.hostFeatures.systemReports.last?.osBuild == "updated-build" }
        await fixture.disconnect()
        try await eventually { !fixture.guest.isConnected }
        #expect(fixture.guestFeatures.systemObserverRemovals == 1)
        #expect(fixture.guestFeatures.postSystemChange == nil)
        fixture.guestFeatures.systemInformation.computerName = "Renamed Guest"
        await fixture.hostConnection.transition(.connected)
        await fixture.guestConnection.transition(.connected)
        try await eventually { fixture.hostFeatures.systemReports.last?.computerName == "Renamed Guest" }
        await fixture.stop()
        #expect(fixture.guestFeatures.systemObserverRegistrations == fixture.guestFeatures.systemObserverRemovals)
    }

    @Test func systemInformationRejectsStaleOutOfOrderAndWrongEndpointMessages() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        let token = try #require(await fixture.guestConnection.token)
        let fresh = GuestSystemInformation(osVersion: "27.0", osBuild: "new")
        try await fixture.guestConnection.send(SystemInformationUpdate(session: token, revision: 20, information: fresh))
        try await eventually { fixture.hostFeatures.systemReports.last == fresh }
        let count = fixture.hostFeatures.systemReports.count
        let stale = GuestSystemInformation(osVersion: "old")
        try await fixture.guestConnection.send(SystemInformationUpdate(session: UUID(), revision: 30, information: stale))
        try await fixture.guestConnection.send(SystemInformationUpdate(session: token, revision: 19, information: stale))
        try await fixture.guestConnection.send(SystemInformationUpdate(session: token, revision: 20, information: stale))
        fixture.guest.onSystemInformation = { _ in Issue.record("Guests must not accept host system information") }
        try await fixture.hostConnection.send(SystemInformationUpdate(session: token, revision: 40, information: stale))
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.hostFeatures.systemReports.count == count)
        await fixture.stop()
    }

    @Test func systemInformationWaitsForCapabilityAndRetriesAfterCollectionFailure() async throws {
        let connection = TestConnection()
        let peer = TestConnection()
        await connection.connect(to: peer)
        let context = GuestServiceContext(connection: connection, endpoint: .guest, requestTimeout: .seconds(1))
        context.session = UUID()
        var collections = 0
        var observed = false
        var removed = false
        let service = SystemInformationGuestService(context: context, collect: {
            collections += 1
            if collections == 1 { throw TestFailure.deadline }
            return GuestSystemInformation(osVersion: "26.0")
        }, observe: { _ in
            observed = true
            return { removed = true }
        }, refreshInterval: .milliseconds(20))
        service.activate(notifications: [])
        #expect(!observed)
        #expect(collections == 0)
        context.hostCapabilities = [SystemInformationGuestService.capability]
        service.activate(notifications: [])
        try await eventually { collections >= 2 }
        service.invalidate()
        await service.drain()
        #expect(removed)
        let finalCount = collections
        try await Task.sleep(for: .milliseconds(50))
        #expect(collections == finalCount)
    }

    @Test func terminationSendsLatestSystemInformation() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        fixture.guestFeatures.systemInformation.computerName = "Before Shutdown"
        await GuestHostSession(engine: fixture.guest).prepareForTermination()
        try await eventually { fixture.hostFeatures.systemReports.last?.computerName == "Before Shutdown" }
        #expect(!fixture.guest.isConnected)
        await fixture.host.stop()
    }

    @Test func defaultsServiceWorksWithoutClipboardOrSessionEngine() async throws {
        let hostConnection = TestConnection()
        let guestConnection = TestConnection()
        await hostConnection.connect(to: guestConnection)
        await guestConnection.connect(to: hostConnection)
        let token = UUID()
        let hostContext = GuestServiceContext(connection: hostConnection, endpoint: .host, requestTimeout: .seconds(1))
        let guestContext = GuestServiceContext(connection: guestConnection, endpoint: .guest, requestTimeout: .seconds(1))
        for context in [hostContext, guestContext] {
            context.session = token
            context.isConnected = true
        }
        let features = TestFeatures()
        let host = DefaultsGuestService(context: hostContext, exportDomain: { _, url in
            try Data("exported".utf8).write(to: url)
        }, importDomain: { _, _ in Issue.record("Host must not import") })
        let guest = DefaultsGuestService(context: guestContext, exportDomain: { _, _ in
            Issue.record("Guest must not export")
        }, importDomain: { domain, url in features.imported[domain] = try Data(contentsOf: url) })
        let subscriptions = host.subscriptions() + guest.subscriptions()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for subscription in subscriptions { group.addTask { await subscription() } }
            defer { group.cancelAll() }
            try await guest.importDomain("example.domain")
            #expect(features.imported["example.domain"] == Data("exported".utf8))
            host.invalidate()
            guest.invalidate()
            await host.drain()
            await guest.drain()
        }
    }

    @Test func hostClipboardWinsAndRelaysWithoutEcho() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        #expect(fixture.guestClipboard.items == clipboard("host"))
        fixture.guestClipboard.write(clipboard("guest edit"))
        try await eventually { fixture.hostClipboard.items == clipboard("guest edit") }
        fixture.hostClipboard.write(clipboard("host edit"))
        fixture.coordinator.poll()
        try await eventually { fixture.guestClipboard.items == clipboard("host edit") }
        let count = await fixture.guestConnection.sentClipboardCount
        try await Task.sleep(for: .milliseconds(600))
        #expect(await fixture.guestConnection.sentClipboardCount == count)
        await fixture.stop()
        #expect(!fixture.guest.isConnected)
        #expect(fixture.guestFeatures.notificationRegistrations == fixture.guestFeatures.notificationRemovals)
        #expect(await fixture.guestConnection.running == false)
    }

    @Test func clipboardRelayCanBeDisabledAndVMEventsStaySeparate() async throws {
        let first = await SessionFixture.make()
        let second = await SessionFixture.make(coordinator: first.coordinator)
        try await first.connect()
        try await second.connect()
        first.guestClipboard.write(clipboard("shared"))
        try await eventually { second.guestClipboard.items == clipboard("shared") }
        #expect(first.hostFeatures.pictures.count == 1)
        #expect(second.hostFeatures.pictures.count == 1)
        first.guestFeatures.postNotification?("com.apple.shieldWindowRaised")
        try await eventually { first.hostFeatures.notifications.count == 1 }
        #expect(second.hostFeatures.notifications.isEmpty)
        await first.stop()
        await second.stop()

        let disabled = await SessionFixture.make(relay: false)
        let other = await SessionFixture.make(coordinator: disabled.coordinator)
        try await disabled.connect()
        try await other.connect()
        disabled.guestClipboard.write(clipboard("private"))
        try await eventually { disabled.hostClipboard.items == clipboard("private") }
        #expect(other.guestClipboard.items == clipboard("host"))
        await disabled.stop()
        await other.stop()
    }

    @Test func reconnectRefreshesStateAndRejectsStaleMessages() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        let oldToken = try #require(await fixture.guestConnection.token)
        await fixture.disconnect()
        try await eventually { !fixture.guest.isConnected }
        #expect(fixture.guestFeatures.notificationRemovals == 1)
        fixture.hostClipboard.write(clipboard("while disconnected"))
        await fixture.hostConnection.transition(.connected)
        await fixture.guestConnection.transition(.connected)
        try await eventually { fixture.guest.isConnected && fixture.guestFeatures.notificationRegistrations == 2 }
        #expect(fixture.guestClipboard.items == clipboard("while disconnected"))
        try await fixture.hostConnection.send(ClipboardUpdate(session: oldToken, revision: 999, items: clipboard("stale")))
        try await fixture.guestConnection.send(DesktopPictureUpdate(session: oldToken, type: "public.heic", content: Data([9])))
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.guestClipboard.items == clipboard("while disconnected"))
        #expect(fixture.hostFeatures.pictures.allSatisfy { $0.content == Data([1, 2, 3]) })
        await fixture.stop()
        try await fixture.connect()
        await fixture.stop()
        #expect(fixture.guestFeatures.notificationRegistrations == fixture.guestFeatures.notificationRemovals)
    }

    @Test func oversizedClipboardUsesFilesAndCleansThemUp() async throws {
        let large = [ClipboardItem(type: "public.png", data: Data(repeating: 0xA5, count: 7 * 1024 * 1024))]
        let fixture = await SessionFixture.make(hostItems: large)
        try await fixture.connect()
        #expect(fixture.guestClipboard.items == large)
        #expect(await fixture.hostConnection.sentFiles == 1)
        fixture.guestClipboard.write(large + clipboard("different"))
        try await eventually { fixture.hostClipboard.items == large + clipboard("different") }
        #expect(await fixture.guestConnection.sentFiles == 1)
        await fixture.stop()
        let files = await fixture.hostConnection.files + fixture.guestConnection.files
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func newerClipboardSupersedesSlowTransfer() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        await fixture.hostConnection.delayTransfers(by: .seconds(2))
        fixture.hostClipboard.write([ClipboardItem(type: "public.png", data: Data(repeating: 4, count: 7 * 1024 * 1024))])
        fixture.coordinator.poll()
        try await eventually { await fixture.guestConnection.receivedFiles > 0 }
        fixture.hostClipboard.write(clipboard("newer"))
        fixture.coordinator.poll()
        try await eventually { fixture.guestClipboard.items == clipboard("newer") }
        await fixture.stop()
        let files = await fixture.hostConnection.files + fixture.guestConnection.files
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func initialSnapshotWinsButLaterTransfersPreserveLocalEdits() async throws {
        let large = [ClipboardItem(type: "public.png", data: Data(repeating: 1, count: 7 * 1024 * 1024))]
        let fixture = await SessionFixture.make(hostItems: large)
        await fixture.hostConnection.delayTransfers(by: .milliseconds(200))
        fixture.host.start()
        fixture.guest.start()
        try await eventually { await fixture.guestConnection.receivedFiles == 1 }
        fixture.guestClipboard.write(clipboard("edit during initialization"))
        try await eventually { fixture.guestClipboard.items == large }

        fixture.hostClipboard.write(large + clipboard("another snapshot"))
        fixture.coordinator.poll()
        try await eventually { await fixture.guestConnection.receivedFiles == 2 }
        fixture.guestClipboard.write(clipboard("keep this local edit"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.guestClipboard.items == clipboard("keep this local edit"))
        await fixture.stop()
    }

    @Test func defaultsRequestsAreCorrelatedAndLargeExportsUseFiles() async throws {
        let fixture = await SessionFixture.make()
        fixture.hostFeatures.defaults["small"] = Data("small plist".utf8)
        fixture.hostFeatures.defaults["large"] = Data(repeating: 7, count: 7 * 1024 * 1024)
        try await fixture.connect()
        async let first: Void = fixture.guest.importDomain("small")
        async let second: Void = fixture.guest.importDomain("large")
        try await first
        try await second
        #expect(fixture.guestFeatures.imported == fixture.hostFeatures.defaults)
        #expect(await fixture.hostConnection.sentFiles == 1)
        await #expect(throws: GuestSessionError.self) { try await fixture.guest.importDomain("missing") }
        await fixture.stop()
        let files = await fixture.hostConnection.files + fixture.guestConnection.files
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func defaultsTimeoutCancellationAndDisconnectDoNotImport() async throws {
        let fixture = await SessionFixture.make(timeout: .milliseconds(100))
        fixture.hostFeatures.exportDelay = .seconds(5)
        fixture.hostFeatures.defaults["slow"] = Data([1])
        try await fixture.connect()
        await #expect(throws: VMBridgeError.requestTimedOut) { try await fixture.guest.importDomain("slow") }
        let cancelled = Task { try await fixture.guest.importDomain("slow") }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let disconnected = Task { try await fixture.guest.importDomain("slow") }
        try await Task.sleep(for: .milliseconds(20))
        await fixture.disconnect()
        do { try await disconnected.value; Issue.record("Disconnected import succeeded") } catch { }
        #expect(fixture.guestFeatures.imported.isEmpty)
        await fixture.stop()
    }

    @Test func failedTransferLeavesClipboardUntouched() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        let token = try #require(await fixture.guestConnection.token)
        let identity = TransferIdentity(session: token, operation: UUID(), purpose: .clipboard, revision: 100)
        let paths = RecordedPaths()
        fixture.guestConnection.offerInput.yield(.init(metadata: identity.metadata, receive: { url in
            paths.append(url)
            try Data([1]).write(to: url)
            throw VMBridgeError.bulkTransferIntegrityFailure
        }, reject: {}))
        try await eventually { !paths.values.isEmpty && paths.values.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        #expect(fixture.guestClipboard.items == clipboard("host"))
        await fixture.stop()
    }

    @Test func terminationClosesConnectionBeforeJoiningBlockedSend() async throws {
        let fixture = await SessionFixture.make()
        try await fixture.connect()
        await fixture.guestConnection.blockPicturesUntilStop()
        let guest = GuestHostSession(engine: fixture.guest)
        let start = ContinuousClock.now
        await guest.prepareForTermination()
        #expect(start.duration(to: .now) < .seconds(3))
        #expect(await fixture.guestConnection.running == false)
        await fixture.host.stop()
    }
}

@MainActor private func eventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw TestFailure.deadline }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private enum TestFailure: Error { case deadline, missingPeer }
private func clipboard(_ text: String) -> [ClipboardItem] { [.init(type: "public.utf8-plain-text", data: Data(text.utf8))] }

@MainActor private final class TestClipboard: GuestClipboard {
    var items: [ClipboardItem]
    var changeCount = 0
    init(_ items: [ClipboardItem]) { self.items = items }
    func read() -> [ClipboardItem] { items }
    func write(_ items: [ClipboardItem]) { self.items = items; changeCount += 1 }
}

@MainActor private final class TestFeatures {
    var notificationRegistrations = 0
    var notificationRemovals = 0
    var postNotification: (@MainActor (String) -> Void)?
    var pictures: [GuestDesktopPicture] = []
    var notifications: [String] = []
    var defaults: [String: Data] = [:]
    var imported: [String: Data] = [:]
    var exportDelay: Duration = .zero
    var systemInformation = GuestSystemInformation(osVersion: "26.0", osBuild: "25A1", sipDescription: "System Integrity Protection status: enabled.")
    var systemReports: [GuestSystemInformation] = []
    var postSystemChange: (@MainActor () -> Void)?
    var systemObserverRegistrations = 0
    var systemObserverRemovals = 0
    var isDarkModeEnabled = false
    var appearanceFails = false
    var appliedAppearances: [Bool] = []
    var postAppearanceChange: (@MainActor () -> Void)?
    var appearanceObserverRegistrations = 0
    var appearanceObserverRemovals = 0

    func providers(clipboard: TestClipboard) -> GuestFeatureProviders {
        .init(clipboard: clipboard, notifications: { [self] _, receive in
            notificationRegistrations += 1
            postNotification = receive
            return { [self] in notificationRemovals += 1; postNotification = nil }
        }, desktopPicture: { GuestDesktopPicture(type: "public.heic", content: Data([1, 2, 3])) }, exportDefaults: { [self] domain, url in
            if exportDelay > .zero { try await Task.sleep(for: exportDelay) }
            guard let data = defaults[domain] else { throw GuestSessionError.unavailableDomain }
            try data.write(to: url)
        }, importDefaults: { [self] domain, url in imported[domain] = try Data(contentsOf: url) }, systemInformation: { [self] in
            systemInformation
        }, systemInformationChanges: { [self] receive in
            systemObserverRegistrations += 1
            postSystemChange = receive
            return { [self] in systemObserverRemovals += 1; postSystemChange = nil }
        }, appearance: { [self] in isDarkModeEnabled }, setAppearance: { [self] enabled in
            if appearanceFails { throw TestFailure.deadline }
            isDarkModeEnabled = enabled
            appliedAppearances.append(enabled)
            postAppearanceChange?()
        }, appearanceChanges: { [self] receive in
            appearanceObserverRegistrations += 1
            postAppearanceChange = receive
            return { [self] in appearanceObserverRemovals += 1; postAppearanceChange = nil }
        })
    }
}

@MainActor private final class SessionFixture {
    let hostConnection: TestConnection
    let guestConnection: TestConnection
    let coordinator: HostClipboardCoordinator
    let hostClipboard: TestClipboard
    let guestClipboard: TestClipboard
    let hostFeatures = TestFeatures()
    let guestFeatures = TestFeatures()
    let host: GuestSessionEngine
    let guest: GuestSessionEngine

    static func make(coordinator: HostClipboardCoordinator? = nil, relay: Bool = true, hostItems: [ClipboardItem] = clipboard("host"), timeout: Duration = .seconds(30)) async -> SessionFixture {
        let host = TestConnection()
        let guest = TestConnection()
        await host.connect(to: guest)
        await guest.connect(to: host)
        return SessionFixture(host: host, guest: guest, coordinator: coordinator, relay: relay, hostItems: hostItems, timeout: timeout)
    }

    private init(host: TestConnection, guest: TestConnection, coordinator: HostClipboardCoordinator?, relay: Bool, hostItems: [ClipboardItem], timeout: Duration) {
        hostConnection = host
        guestConnection = guest
        hostClipboard = coordinator?.clipboard as? TestClipboard ?? TestClipboard(hostItems)
        guestClipboard = TestClipboard(clipboard("old guest"))
        self.coordinator = coordinator ?? HostClipboardCoordinator(clipboard: hostClipboard, relayEnabled: { relay })
        self.host = GuestSessionEngine(connection: host, endpoint: .host, hostClipboard: self.coordinator, providers: hostFeatures.providers(clipboard: hostClipboard))
        self.guest = GuestSessionEngine(connection: guest, endpoint: .guest, providers: guestFeatures.providers(clipboard: guestClipboard), requestTimeout: timeout)
        self.host.onDesktopPicture = { [hostFeatures] in hostFeatures.pictures.append($0) }
        self.host.onSystemInformation = { [hostFeatures] in hostFeatures.systemReports.append($0) }
        self.host.onNotification = { [hostFeatures] in hostFeatures.notifications.append($0) }
    }

    func connect() async throws {
        host.start()
        guest.start()
        try await eventually { self.guest.isConnected && self.guestFeatures.postNotification != nil && !self.hostFeatures.pictures.isEmpty && !self.hostFeatures.systemReports.isEmpty && self.guestClipboard.items == self.hostClipboard.items }
    }
    func disconnect() async {
        await hostConnection.transition(.disconnected)
        await guestConnection.transition(.disconnected)
    }
    func stop() async { await guest.stop(); await host.stop() }
}

private final class RecordedPaths: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [URL]())
    var values: [URL] { storage.withLock { $0 } }
    func append(_ url: URL) { storage.withLock { $0.append(url) } }
}

private final class MessageBus: Sendable {
    private let streams = OSAllocatedUnfairLock(initialState: [String: [UUID: AsyncStream<Data>.Continuation]]())
    func subscribe<M: VMMessage>(_ type: M.Type) -> AsyncStream<M> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        streams.withLock { $0[M.messageID, default: [:]][id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.streams.withLock { $0[M.messageID]?[id] = nil } }
        return AsyncStream(unfolding: {
            var iterator = stream.makeAsyncIterator()
            guard let data = await iterator.next() else { return nil }
            return try? JSONDecoder().decode(M.self, from: data)
        })
    }
    func send<M: VMMessage>(_ message: M) throws {
        let data = try JSONEncoder().encode(message)
        let subscribers = streams.withLock { Array(($0[M.messageID] ?? [:]).values) }
        for continuation in subscribers { continuation.yield(data) }
    }
}

private struct TestReply: Sendable {
    let stream: AsyncThrowingStream<Data, Error>
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    init() { (stream, continuation) = AsyncThrowingStream.makeStream() }
    func reply<M: VMMessage>(_ message: M) throws { continuation.yield(try JSONEncoder().encode(message)); continuation.finish() }
    func value() async throws -> Data {
        for try await data in stream { return data }
        throw CancellationError()
    }
}

private actor TestConnection: GuestConnection {
    nonisolated let stateInput = TestEvents<VMConnectionState>()
    nonisolated var state: AsyncStream<VMConnectionState> { stateInput.stream() }
    nonisolated private let requestBus = RequestBus()
    nonisolated func requests<M: VMMessage, R: VMMessage>(of type: M.Type, reply: R.Type) -> AsyncStream<GuestRequest<M, R>> {
        requestBus.subscribe(type, reply: reply)
    }
    nonisolated let offerInput = TestEvents<GuestFileOffer>()
    nonisolated var fileOffers: AsyncStream<GuestFileOffer> { offerInput.stream() }
    nonisolated private let bus = MessageBus()
    private var peer: TestConnection?
    private var transferDelay: Duration = .zero
    private var appearanceRequestDelay: Duration = .zero
    private(set) var sentAppearanceRequests: [Bool] = []
    private var blockPictures = false
    private var pictureWaiter: CheckedContinuation<Void, Error>?
    private(set) var token: UUID?
    private(set) var sentClipboardCount = 0
    private(set) var sentFiles = 0
    private(set) var receivedFiles = 0
    private(set) var files: [URL] = []
    private(set) var running = false

    func connect(to peer: TestConnection) { self.peer = peer }
    func delayTransfers(by delay: Duration) { transferDelay = delay }
    func delayAppearanceRequests(by delay: Duration) { appearanceRequestDelay = delay }
    func blockPicturesUntilStop() { blockPictures = true }
    func transition(_ state: VMConnectionState) { stateInput.yield(state) }
    nonisolated func messages<M: VMMessage>(of type: M.Type) -> AsyncStream<M> { bus.subscribe(type) }
    func send<M: VMMessage>(_ message: M) async throws {
        if message is DesktopPictureUpdate, blockPictures {
            try await withCheckedThrowingContinuation { pictureWaiter = $0 }
        }
        try Task.checkCancellation()
        guard let peer else { throw TestFailure.missingPeer }
        if message is ClipboardUpdate { sentClipboardCount += 1 }
        try peer.bus.send(message)
    }
    func request<M: VMMessage, R: VMMessage>(_ message: M, reply: R.Type, timeout: Duration) async throws -> R {
        try Task.checkCancellation()
        if let command = message as? SetGuestAppearance {
            sentAppearanceRequests.append(command.isDarkModeEnabled)
            if appearanceRequestDelay > .zero { try await Task.sleep(for: appearanceRequestDelay) }
        }
        guard let peer else { throw TestFailure.missingPeer }
        let response = TestReply()
        if let message = message as? InitializeGuest { token = message.session }
        try peer.requestBus.send(message, response: response)
        let data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await response.value() }
            group.addTask { try await Task.sleep(for: timeout); throw VMBridgeError.requestTimedOut }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
    private func receivedFile(_ url: URL) { receivedFiles += 1; files.append(url) }
    func sendFile(at url: URL, metadata: BulkTransferMetadata) async throws {
        guard let peer else { throw TestFailure.missingPeer }
        sentFiles += 1
        files.append(url)
        let completion = TestReply()
        let delay = transferDelay
        peer.offerInput.yield(.init(metadata: metadata, receive: { destination in
            await peer.receivedFile(destination)
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: url, to: destination)
                completion.continuation.yield(Data())
                completion.continuation.finish()
            } catch {
                completion.continuation.finish(throwing: error)
                throw error
            }
        }, reject: { completion.continuation.finish(throwing: VMBridgeError.bulkTransferRejected) }))
        _ = try await completion.value()
    }
    func run() async throws {
        running = true
        stateInput.yield(.connected)
        do { try await Task.sleep(for: .seconds(3600)) } catch { }
        running = false
        pictureWaiter?.resume(throwing: GuestSessionError.disconnected)
        pictureWaiter = nil
        stateInput.yield(.stopped)
    }
}

private final class TestEvents<Element: Sendable>: Sendable {
    private let subscribers = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<Element>.Continuation]())
    func stream() -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        subscribers.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.subscribers.withLock { $0[id] = nil } }
        return stream
    }
    func yield(_ value: Element) {
        let continuations = subscribers.withLock { Array($0.values) }
        for continuation in continuations { continuation.yield(value) }
    }
}

private final class RequestBus: Sendable {
    private struct Envelope: Sendable {
        let data: Data
        let response: TestReply
    }
    private let streams = OSAllocatedUnfairLock(initialState: [String: [UUID: AsyncStream<Envelope>.Continuation]]())
    func subscribe<M: VMMessage, R: VMMessage>(_ type: M.Type, reply: R.Type) -> AsyncStream<GuestRequest<M, R>> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Envelope>.makeStream()
        streams.withLock { $0[M.messageID, default: [:]][id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.streams.withLock { $0[M.messageID]?[id] = nil } }
        return AsyncStream(unfolding: {
            var iterator = stream.makeAsyncIterator()
            guard let envelope = await iterator.next(),
                  let payload = try? JSONDecoder().decode(M.self, from: envelope.data) else { return nil }
            return GuestRequest(payload: payload, reply: { try envelope.response.reply($0) })
        })
    }
    func send<M: VMMessage>(_ message: M, response: TestReply) throws {
        let envelope = Envelope(data: try JSONEncoder().encode(message), response: response)
        let subscribers = streams.withLock { Array(($0[M.messageID] ?? [:]).values) }
        for continuation in subscribers { continuation.yield(envelope) }
    }
}
