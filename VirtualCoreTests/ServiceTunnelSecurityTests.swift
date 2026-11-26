import Foundation
import ManagedPreferencesKit
import Testing
import VirtualWormhole
@testable import VirtualCore

/// Stands in for the host's Keychain, which a test bundle can't use.
private final class HostApprovals: @unchecked Sendable {
    private var digests: [String: Data] = [:]
    var store: SettingApprovals {
        SettingApprovals(digest: { self.digests[$0] }, record: { self.digests[$1] = $0 })
    }
}

private struct PolicyStore: ManagedPreferenceStore {
    var values: [String: Any]
    func value(forKey key: String, domain: String) -> Any? { values[key] }
    func valueIsForced(forKey key: String, domain: String) -> Bool { values[key] != nil }
}

private final class ChosenLevel: @unchecked Sendable {
    var value: ServiceTunnelSecurityLevel = .reviewAll
}

struct ServiceTunnelSecurityTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let host = HostApprovals()
    private let storage = SecuritySettingsStorage.inMemory()
    private let level = ChosenLevel()

    private let toHostPort = ServiceTunnel(listensOnHost: false, listener: .tcp(8000), destination: .tcp(5432))
    private let toHostSocket = ServiceTunnel(listensOnHost: false, listener: .tcp(8001), destination: .unix("/private/tmp/example.sock"))

    private var setting: ApprovedVMSetting<[ServiceTunnel]> { VBVirtualMachine.tunnelSetting(approvals: host.store) }

    private var security: ServiceTunnelSecurity {
        let level = level
        return ServiceTunnelSecurity(
            level: { level.value },
            isRemembered: { (try? storage.isRemembered($0)) ?? false },
            remember: { try storage.remember($0) }
        )
    }

    private func withVM(_ body: (VBVirtualMachine) throws -> Void) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = try VBVirtualMachine(bundleURL: root.appendingPathComponent("Original.vbvm"), isNewInstall: true)
        try vm.saveMetadata()
        try body(vm)
    }

    private func state(of vm: VBVirtualMachine) -> ApprovedSettingState<[ServiceTunnel]> {
        vm.serviceTunnelSettings(setting: setting, security: security)
    }

    private func runnable(in vm: VBVirtualMachine) throws -> [ServiceTunnel] {
        try vm.runnableServiceTunnels(setting: setting, security: security)
    }

    /// Saves tunnels the way a bundle brought in from elsewhere has them: on disk, with no approval on this host.
    private func saveUnapproved(_ tunnels: [ServiceTunnel], in vm: VBVirtualMachine) throws {
        try setting.store(tunnels, in: vm)
    }

    // MARK: Saved level

    @Test func levelIsTheStrictestUnlessItWasReadBackIntact() throws {
        #expect(storage.tunnelLevel() == .reviewAll)
        for level in ServiceTunnelSecurityLevel.allCases {
            try storage.setTunnelLevel(level)
            #expect(storage.tunnelLevel() == level)
        }

        var invalid = SecuritySettingsStorage.inMemory()
        invalid.savedLevel = { Data("Whatever".utf8) }
        #expect(invalid.tunnelLevel() == .reviewAll)

        var failing = SecuritySettingsStorage.inMemory()
        failing.savedLevel = { throw Failure("Keychain unavailable") }
        #expect(failing.tunnelLevel() == .reviewAll)
    }

    @Test func levelsAreOrderedByHowMuchIsReviewed() {
        #expect(ServiceTunnelSecurityLevel.reviewNone < .reviewNew)
        #expect(ServiceTunnelSecurityLevel.reviewNew < .reviewAll)
        #expect(ServiceTunnelSecurityLevel.allCases.max() == .strictest)
    }

    @Test func organizationOnlyEverAddsReview() throws {
        func effective(_ chosen: ServiceTunnelSecurityLevel, minimum: ServiceTunnelSecurityLevel?) throws -> ServiceTunnelSecurityLevel {
            try storage.setTunnelLevel(chosen)
            return ServiceTunnelSecurity(storage: storage) { minimum }.level()
        }
        #expect(try effective(.reviewNone, minimum: nil) == .reviewNone)
        #expect(try effective(.reviewNone, minimum: .reviewNew) == .reviewNew)
        #expect(try effective(.reviewNone, minimum: .reviewAll) == .reviewAll)
        #expect(try effective(.reviewAll, minimum: .reviewNone) == .reviewAll)
        #expect(try effective(.reviewAll, minimum: .reviewNew) == .reviewAll)
    }

    @Test func managedMinimumFailsClosedOnValuesItDoesNotUnderstand() {
        func minimum(_ values: [String: Any]) -> ServiceTunnelSecurityLevel? {
            VirtualBuddyManagedPreferences.serviceTunnelMinimumReviewLevel(
                preferences: VirtualBuddyManagedPreferences.schema.reader(store: PolicyStore(values: values))
            )
        }
        #expect(minimum([:]) == nil)
        #expect(minimum(["ServiceTunnelMinimumReviewLevel": "Never"]) == .reviewNone)
        #expect(minimum(["ServiceTunnelMinimumReviewLevel": "NewTunnels"]) == .reviewNew)
        #expect(minimum(["ServiceTunnelMinimumReviewLevel": "EveryChange"]) == .reviewAll)
        #expect(minimum(["ServiceTunnelMinimumReviewLevel": "everychange"]) == .reviewAll)
        #expect(minimum(["ServiceTunnelMinimumReviewLevel": 2]) == .reviewAll)
        #expect(minimum(["ServiceTunnelMinimumReviewLevel": true]) == .reviewAll)
    }

    // MARK: Remembered tunnels

    @Test func tunnelsAreRememberedByDirectionAndHostEndpointOnly() throws {
        try storage.remember([ServiceTunnelIdentity(toHostPort)])
        let otherGuestPort = ServiceTunnel(listensOnHost: false, listener: .tcp(9999), destination: .tcp(5432))
        let listeningOnTheSamePort = ServiceTunnel(listensOnHost: true, listener: .tcp(5432), destination: .tcp(8000))
        let overIPv6 = ServiceTunnel(listensOnHost: false, listener: .tcp(8000), destination: .tcp6(5432))
        #expect(try storage.isRemembered(ServiceTunnelIdentity(otherGuestPort)))
        #expect(try !storage.isRemembered(ServiceTunnelIdentity(listeningOnTheSamePort)))
        #expect(try !storage.isRemembered(ServiceTunnelIdentity(overIPv6)))
        #expect(try !storage.isRemembered(ServiceTunnelIdentity(toHostSocket)))

        try storage.remember([ServiceTunnelIdentity(toHostPort), ServiceTunnelIdentity(otherGuestPort)])
        #expect(try storage.rememberedTunnelCount() == 1)
        try storage.forgetTunnels()
        #expect(try storage.rememberedTunnelCount() == 0)
        #expect(try !storage.isRemembered(ServiceTunnelIdentity(toHostPort)))
    }

    @Test func approvingRemembersTunnelsUnlessNothingIsReviewed() throws {
        try withVM { vm in
            level.value = .reviewNone
            try vm.approveServiceTunnels([toHostPort], setting: setting, security: security)
            #expect(try storage.rememberedTunnelCount() == 0)
            #expect(try setting.approvedValue(in: vm) == nil)

            level.value = .reviewAll
            try vm.approveServiceTunnels([toHostPort], setting: setting, security: security)
            #expect(try storage.isRemembered(ServiceTunnelIdentity(toHostPort)))
            #expect(try setting.approvedValue(in: vm) == [toHostPort])
        }
    }

    @Test func approvalStandsWhenRememberingFails() throws {
        var security = security
        security.remember = { _ in throw Failure("Keychain unavailable") }
        try withVM { vm in
            try vm.approveServiceTunnels([toHostPort], setting: setting, security: security)
            #expect(vm.serviceTunnelSettings(setting: setting, security: security) == .approved([toHostPort]))
        }
    }

    // MARK: Reading under each level

    @Test func everyChangeIsReviewedByDefault() throws {
        try withVM { vm in
            try storage.remember([ServiceTunnelIdentity(toHostPort)])
            try saveUnapproved([toHostPort], in: vm)
            #expect(state(of: vm) == .needsApproval([toHostPort]))
            #expect(try runnable(in: vm).isEmpty)
        }
    }

    @Test func rememberedTunnelsRunWithoutReviewOnlyWhileNewTunnelsAreReviewed() throws {
        try withVM { vm in
            level.value = .reviewNew
            try saveUnapproved([toHostPort, toHostSocket], in: vm)
            #expect(state(of: vm) == .needsApproval([toHostPort, toHostSocket]))

            /// One tunnel nobody reviewed keeps the whole record waiting.
            try storage.remember([ServiceTunnelIdentity(toHostPort)])
            #expect(state(of: vm) == .needsApproval([toHostPort, toHostSocket]))
            #expect(try runnable(in: vm).isEmpty)

            try storage.remember([ServiceTunnelIdentity(toHostSocket)])
            #expect(state(of: vm) == .approved([toHostPort, toHostSocket]))
            #expect(try runnable(in: vm) == [toHostPort, toHostSocket])
            /// Nothing was recorded, so more review and forgetting both take it back.
            #expect(try setting.approvedValue(in: vm) == nil)

            level.value = .reviewAll
            #expect(state(of: vm) == .needsApproval([toHostPort, toHostSocket]))
            #expect(try runnable(in: vm).isEmpty)

            level.value = .reviewNew
            try storage.forgetTunnels()
            #expect(state(of: vm) == .needsApproval([toHostPort, toHostSocket]))
            #expect(try runnable(in: vm).isEmpty)
        }
    }

    @Test func approvedTunnelsKeepRunningWhenReviewedTunnelsAreForgotten() throws {
        try withVM { vm in
            level.value = .reviewNew
            try vm.approveServiceTunnels([toHostPort], setting: setting, security: security)
            try storage.forgetTunnels()
            #expect(state(of: vm) == .approved([toHostPort]))
            #expect(try runnable(in: vm) == [toHostPort])
        }
    }

    @Test func withoutReviewTunnelsRunAsSavedAndAreReviewedOnceReviewIsBack() throws {
        try withVM { vm in
            level.value = .reviewNone
            #expect(state(of: vm) == .missing)
            #expect(try runnable(in: vm).isEmpty)

            try saveUnapproved([toHostPort], in: vm)
            #expect(state(of: vm) == .approved([toHostPort]))
            #expect(try runnable(in: vm) == [toHostPort])

            try vm.approveServiceTunnels([toHostPort, toHostSocket], setting: setting, security: security)
            #expect(try runnable(in: vm) == [toHostPort, toHostSocket])

            for stricter in [ServiceTunnelSecurityLevel.reviewNew, .reviewAll] {
                level.value = stricter
                #expect(state(of: vm) == .needsApproval([toHostPort, toHostSocket]))
                #expect(try runnable(in: vm).isEmpty)
            }
        }
    }

    @Test func invalidRecordsNeverRunWhateverTheLevel() throws {
        try withVM { vm in
            try saveUnapproved([toHostPort], in: vm)
            try Data("not a property list".utf8).write(to: vm.metadataFileURL(setting.filename))
            for level in ServiceTunnelSecurityLevel.allCases {
                self.level.value = level
                guard case .unavailable = state(of: vm) else {
                    Issue.record("An unreadable record was offered at \(level)")
                    continue
                }
                #expect(throws: (any Error).self) { try runnable(in: vm) }
            }
        }
    }

    // MARK: Requests from the guest

    @Test func guestRequestsAreNeverAddedWhileEveryChangeIsReviewed() throws {
        try withVM { vm in
            try storage.remember([ServiceTunnelIdentity(toHostPort)])
            #expect(!vm.acceptProposedServiceTunnel(toHostPort, setting: setting, security: security))
            #expect(state(of: vm) == .missing)
        }
    }

    @Test func rememberedGuestRequestsAreAddedWhileNewTunnelsAreReviewed() throws {
        try withVM { vm in
            level.value = .reviewNew
            #expect(!vm.acceptProposedServiceTunnel(toHostPort, setting: setting, security: security))
            #expect(state(of: vm) == .missing)

            try storage.remember([ServiceTunnelIdentity(toHostPort)])
            #expect(vm.acceptProposedServiceTunnel(toHostPort, setting: setting, security: security))
            #expect(try runnable(in: vm) == [toHostPort])
            #expect(!vm.acceptProposedServiceTunnel(toHostSocket, setting: setting, security: security))
            #expect(try runnable(in: vm) == [toHostPort])
        }
    }

    @Test func addingARememberedRequestKeepsTheApprovedTunnelsRunning() throws {
        try withVM { vm in
            /// Approved before reviewed tunnels were remembered at all.
            try setting.approve([toHostSocket], in: vm)
            try storage.remember([ServiceTunnelIdentity(toHostPort)])
            level.value = .reviewNew
            #expect(vm.acceptProposedServiceTunnel(toHostPort, setting: setting, security: security))
            #expect(try runnable(in: vm) == [toHostSocket, toHostPort])

            /// The request wasn't reviewed for this virtual machine, so the record as a whole no longer is either.
            level.value = .reviewAll
            #expect(state(of: vm) == .needsApproval([toHostSocket, toHostPort]))
        }
    }

    @Test func nothingIsAddedBehindTunnelsWaitingForReview() throws {
        try withVM { vm in
            level.value = .reviewNew
            try saveUnapproved([toHostSocket], in: vm)
            try storage.remember([ServiceTunnelIdentity(toHostPort)])
            #expect(!vm.acceptProposedServiceTunnel(toHostPort, setting: setting, security: security))
            #expect(state(of: vm) == .needsApproval([toHostSocket]))
        }
    }

    @Test func everyGuestRequestIsAddedWithoutReviewAndInvalidOnesAreNot() throws {
        try withVM { (vm: VBVirtualMachine) throws in
            level.value = .reviewNone
            #expect(vm.acceptProposedServiceTunnel(toHostPort, setting: setting, security: security))
            #expect(vm.acceptProposedServiceTunnel(toHostSocket, setting: setting, security: security))
            #expect(try runnable(in: vm) == [toHostPort, toHostSocket])
            #expect(try storage.rememberedTunnelCount() == 0)

            let sameListener = ServiceTunnel(listensOnHost: false, listener: toHostPort.listener, destination: .tcp(22))
            #expect(!vm.acceptProposedServiceTunnel(sameListener, setting: setting, security: security))
            #expect(try runnable(in: vm) == [toHostPort, toHostSocket])
        }
    }
}

@MainActor
struct SecuritySettingsSessionTests {
    private final class Prompt {
        var result: Result<Void, Error> = .success(())
        var count = 0
    }

    private func makeSession(storage: SecuritySettingsStorage = .inMemory(), prompt: Prompt) -> SecuritySettingsSession {
        SecuritySettingsSession(storage: storage) { _ in
            prompt.count += 1
            try prompt.result.get()
        }
    }

    @Test func settingsOnlyChangeWhileUnlocked() async throws {
        let storage = SecuritySettingsStorage.inMemory()
        let prompt = Prompt()
        let session = makeSession(storage: storage, prompt: prompt)
        try storage.remember([ServiceTunnelIdentity(ServiceTunnel(listensOnHost: true, listener: .tcp(8080), destination: .tcp(80)))])

        #expect(!session.isUnlocked)
        #expect(throws: Failure.self) { try session.setTunnelLevel(.reviewNone) }
        #expect(throws: Failure.self) { try session.forgetRememberedTunnels() }
        #expect(storage.tunnelLevel() == .reviewAll)
        #expect(try storage.rememberedTunnelCount() == 1)

        try await session.unlock()
        try await session.unlock()
        #expect(prompt.count == 1)
        try session.setTunnelLevel(.reviewNew)
        #expect(session.tunnelLevel == .reviewNew)
        #expect(storage.tunnelLevel() == .reviewNew)
        #expect(session.rememberedTunnelCount == 1)
        try session.forgetRememberedTunnels()
        #expect(session.rememberedTunnelCount == 0)

        session.lock()
        #expect(throws: Failure.self) { try session.setTunnelLevel(.reviewNone) }
        #expect(storage.tunnelLevel() == .reviewNew)
    }

    @Test func staysLockedWhenTheUserIsNotVerified() async {
        let prompt = Prompt()
        prompt.result = .failure(Failure("Cancelled"))
        let session = makeSession(prompt: prompt)
        await #expect(throws: Failure.self) { try await session.unlock() }
        #expect(!session.isUnlocked)
        #expect(throws: Failure.self) { try session.setTunnelLevel(.reviewNone) }
    }

    @Test func changesReachObserversForAsLongAsTheyListen() async throws {
        let session = makeSession(prompt: Prompt())
        try await session.unlock()
        var changes = 0
        var observation: SecuritySettingsObservation? = session.observeChanges { changes += 1 }
        try session.setTunnelLevel(.reviewNew)
        try session.forgetRememberedTunnels()
        #expect(changes == 2)
        _ = observation
        observation = nil
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        try session.setTunnelLevel(.reviewAll)
        #expect(changes == 2)
    }

    @Test func monitorFollowsTheLevelAndReportsForgottenTunnels() async throws {
        let storage = SecuritySettingsStorage.inMemory()
        let session = makeSession(storage: storage, prompt: Prompt())
        let monitor = ServiceTunnelSecurityMonitor(
            security: ServiceTunnelSecurity(storage: storage) { nil },
            session: session,
            preferences: VirtualBuddyManagedPreferences.schema.reader(store: PolicyStore(values: [:]))
        )
        var changes = 0
        monitor.onChange = { changes += 1 }
        #expect(monitor.level == .reviewAll)
        try await session.unlock()
        try session.setTunnelLevel(.reviewNone)
        #expect(monitor.level == .reviewNone)
        try session.forgetRememberedTunnels()
        #expect(changes == 2)
    }
}
