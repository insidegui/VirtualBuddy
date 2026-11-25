import Foundation
import ManagedPreferencesKit
import Testing
import VirtualWormhole
@testable import VirtualCore

struct ManagedServiceTunnelPreferencesTests {
    private let toHostPort = ServiceTunnel(listensOnHost: false, listener: .tcp(9000), destination: .tcp(5432))
    private let toGuestPort = ServiceTunnel(listensOnHost: true, listener: .tcp(8080), destination: .tcp(3000))
    private let toHostSocket = ServiceTunnel(listensOnHost: false, listener: .tcp(9001), destination: .unix("/var/run/virtualbuddy-tests.sock"))

    private func policy(_ values: [String: Any]) -> ServiceTunnelPolicy {
        VirtualBuddyManagedPreferences.serviceTunnelPolicy(preferences: VirtualBuddyManagedPreferences.schema.reader(store: PolicyStore(values: values)))
    }

    private func permitted(_ values: [String: Any]) -> [ServiceTunnel] {
        [toHostPort, toGuestPort, toHostSocket].filter(policy(values).permits)
    }

    @Test func absentAndFalsePreferencesRestrictNothing() {
        #expect(policy([:]) == .unrestricted)
        #expect(policy([
            "DisableServiceTunnels": false, "DisableServiceTunnelsToHostServices": false, "DisableServiceTunnelsToGuestServices": false,
            "DisableServiceTunnelUnixSockets": false, "DisableServiceTunnelTCPPorts": false, "DisableServiceTunnelRequests": false
        ]) == .unrestricted)
    }

    @Test func eachSwitchSetsItsRestriction() {
        #expect(policy(["DisableServiceTunnels": true]).tunnelsDisabled)
        #expect(policy(["DisableServiceTunnelRequests": true]).requestsDisabled)
        #expect(permitted(["DisableServiceTunnels": true]).isEmpty)
        #expect(permitted(["DisableServiceTunnelsToHostServices": true]) == [toGuestPort])
        #expect(permitted(["DisableServiceTunnelsToGuestServices": true]) == [toHostPort, toHostSocket])
        #expect(permitted(["DisableServiceTunnelUnixSockets": true]) == [toHostPort, toGuestPort])
        #expect(permitted(["DisableServiceTunnelTCPPorts": true]).isEmpty)
        #expect(permitted(["DisableServiceTunnelRequests": true]).count == 3)
    }

    @Test func listsLimitHostPortsAndSocketPaths() {
        #expect(permitted(["ServiceTunnelAllowedHostPorts": ["5432"]]) == [toHostPort, toHostSocket])
        #expect(permitted(["ServiceTunnelAllowedHostPorts": [5432, "8000-8100"]]) == [toHostPort, toGuestPort, toHostSocket])
        #expect(permitted(["ServiceTunnelDeniedHostPorts": ["8080"]]) == [toHostPort, toHostSocket])
        #expect(permitted(["ServiceTunnelAllowedHostPorts": [String]()]) == [toHostSocket])
        #expect(permitted(["ServiceTunnelAllowedHostSocketPaths": ["/var/run/"]]).count == 3)
        #expect(permitted(["ServiceTunnelAllowedHostSocketPaths": ["/var/empty/"]]) == [toHostPort, toGuestPort])
        #expect(permitted(["ServiceTunnelDeniedHostSocketPaths": ["/var/run/virtualbuddy-tests.sock"]]) == [toHostPort, toGuestPort])
    }

    @Test func listsThatCannotBeReadNeverPermitMore() {
        for unreadable: Any in ["5432", 5432, true, ["nested": "value"], [true], [["5432"]], [5432.5]] {
            #expect(permitted(["ServiceTunnelAllowedHostPorts": unreadable]) == [toHostSocket])
            #expect(permitted(["ServiceTunnelDeniedHostPorts": unreadable]) == [toHostSocket])
        }
        for unreadable: Any in ["/var/run/", 1, true, [1], [["/var/run/"]]] {
            #expect(permitted(["ServiceTunnelAllowedHostSocketPaths": unreadable]) == [toHostPort, toGuestPort])
            #expect(permitted(["ServiceTunnelDeniedHostSocketPaths": unreadable]) == [toHostPort, toGuestPort])
        }
        /// One bad entry doesn't undo the good ones in a list of allowed ports, and denies everything in a list of denied ones.
        #expect(permitted(["ServiceTunnelAllowedHostPorts": ["5432", "postgres"]]) == [toHostPort, toHostSocket])
        #expect(permitted(["ServiceTunnelDeniedHostPorts": ["8080", "postgres"]]) == [toHostSocket])
    }

    @Test func monitorOnlyReportsChangesToTheTunnelPolicy() async throws {
        let store = MutableStore()
        let monitor = await ServiceTunnelPolicyMonitor(preferences: VirtualBuddyManagedPreferences.schema.reader(store: store))
        let changes = Changes()
        await MainActor.run { monitor.onChange = { changes.policies.append($0) } }
        #expect(await monitor.policy == .unrestricted)

        store.values["DisableSharedFolders"] = true
        await monitor.refresh()
        #expect(changes.policies.isEmpty)

        store.values["DisableServiceTunnelUnixSockets"] = true
        await monitor.refresh()
        await monitor.refresh()
        #expect(changes.policies.count == 1)
        #expect(await monitor.policy.unixSocketsDisabled)

        store.values["DisableServiceTunnelUnixSockets"] = nil
        await monitor.refresh()
        #expect(changes.policies.last == .unrestricted)
    }

    @Test func administratorDocumentationDescribesTheLists() throws {
        let schema = VirtualBuddyManagedPreferences.schema
        let markdown = schema.markdownDocumentation()
        let manifest = try #require(PropertyListSerialization.propertyList(from: schema.profileManifestData(), format: nil) as? [String: Any])
        let subkeys = try #require(manifest["pfm_subkeys"] as? [[String: Any]])
        for key in ["ServiceTunnelAllowedHostPorts", "ServiceTunnelDeniedHostPorts", "ServiceTunnelAllowedHostSocketPaths", "ServiceTunnelDeniedHostSocketPaths"] {
            #expect(markdown.contains(key))
            let entry = try #require(subkeys.first { $0["pfm_name"] as? String == key })
            #expect(entry["pfm_type"] as? String == "array")
            #expect(entry["pfm_default"] == nil)
        }
    }

    private struct PolicyStore: ManagedPreferenceStore {
        var values: [String: Any]
        func value(forKey key: String, domain: String) -> Any? { values[key] }
        func valueIsForced(forKey key: String, domain: String) -> Bool { values[key] != nil }
    }

    private final class MutableStore: ManagedPreferenceStore, @unchecked Sendable {
        var values: [String: Any] = [:]
        func value(forKey key: String, domain: String) -> Any? { values[key] }
        func valueIsForced(forKey key: String, domain: String) -> Bool { values[key] != nil }
    }

    private final class Changes: @unchecked Sendable {
        var policies: [ServiceTunnelPolicy] = []
    }
}
