import Foundation
import ManagedPreferencesKit
import Observation
import VirtualWormhole

public extension VirtualBuddyManagedPreferences {
    /// The service tunnel policy currently in effect, as set by the organization's configuration profile.
    static func serviceTunnelPolicy(preferences: Reader = schema.reader()) -> ServiceTunnelPolicy {
        var policy = ServiceTunnelPolicy()
        policy.tunnelsDisabled = preferences.value(for: .disableServiceTunnels, default: false)
        policy.hostServicesDisabled = preferences.value(for: .disableServiceTunnelsToHostServices, default: false)
        policy.guestServicesDisabled = preferences.value(for: .disableServiceTunnelsToGuestServices, default: false)
        policy.unixSocketsDisabled = preferences.value(for: .disableServiceTunnelUnixSockets, default: false)
        policy.tcpPortsDisabled = preferences.value(for: .disableServiceTunnelTCPPorts, default: false)
        policy.requestsDisabled = preferences.value(for: .disableServiceTunnelRequests, default: false)
        policy.setHostPorts(
            allowed: list(.serviceTunnelAllowedHostPorts, in: preferences, acceptingIntegers: true),
            denied: list(.serviceTunnelDeniedHostPorts, in: preferences, acceptingIntegers: true) ?? []
        )
        policy.setHostSocketPaths(
            allowed: list(.serviceTunnelAllowedHostSocketPaths, in: preferences),
            denied: list(.serviceTunnelDeniedHostSocketPaths, in: preferences) ?? []
        )
        return policy
    }

    /// An entry that every list reads as a mistake: it allows nothing where things are allowed, and denies everything where they're denied.
    private static let unreadableEntry = ""

    /// The entries of a list preference, or `nil` when the organization hasn't set it.
    ///
    /// A list restricts what tunnels can do, so a value that can't be read must not turn into no restriction at all,
    /// which is what falling back to the preference being absent would amount to. Anything unreadable becomes an entry
    /// the policy doesn't understand, and the policy fails closed on those.
    private static func list(_ preference: Preference<[String]>, in preferences: Reader, acceptingIntegers: Bool = false) -> [String]? {
        let resolution = preferences.resolve(preference)
        guard let rawValue = resolution.rawValue else { return nil }
        guard let entries = rawValue as? [Any] else {
            logger.error("\(preference.key, privacy: .public) is not a list. Service tunnels are restricted as if it allowed nothing.")
            return [unreadableEntry]
        }
        return entries.map { entry in
            if let text = entry as? String { return text }
            // A Boolean is a number to the property list, but never a port.
            if acceptingIntegers, let number = entry as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
            logger.error("\(preference.key, privacy: .public) has an entry of the wrong type. Service tunnels are restricted as if it allowed nothing.")
            return unreadableEntry
        }
    }

    /// Calls the handler when any preference that the service tunnel policy is made of may have changed.
    @MainActor
    static func observeServiceTunnelPolicy(
        preferences: Reader = schema.reader(),
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> [ManagedPreferenceObservation] {
        let switches: [Preference<Bool>] = [
            .disableServiceTunnels, .disableServiceTunnelsToHostServices, .disableServiceTunnelsToGuestServices,
            .disableServiceTunnelUnixSockets, .disableServiceTunnelTCPPorts, .disableServiceTunnelRequests
        ]
        let lists: [Preference<[String]>] = [
            .serviceTunnelAllowedHostPorts, .serviceTunnelDeniedHostPorts,
            .serviceTunnelAllowedHostSocketPaths, .serviceTunnelDeniedHostSocketPaths
        ]
        return switches.compactMap { preferences.observeChanges(for: $0, handler: handler) }
            + lists.compactMap { preferences.observeChanges(for: $0, handler: handler) }
    }
}

/// Keeps track of the service tunnel policy while the organization's configuration profile is installed, changed or removed.
@MainActor @Observable
public final class ServiceTunnelPolicyMonitor {
    public private(set) var policy: ServiceTunnelPolicy

    /// Called after the policy has changed. Preferences that have nothing to do with tunnels change all the time, and don't count.
    @ObservationIgnored public var onChange: (@MainActor (ServiceTunnelPolicy) -> Void)?

    @ObservationIgnored private let preferences: VirtualBuddyManagedPreferences.Reader
    @ObservationIgnored private var observations: [ManagedPreferenceObservation] = []

    public init(preferences: VirtualBuddyManagedPreferences.Reader = VirtualBuddyManagedPreferences.schema.reader()) {
        self.preferences = preferences
        policy = VirtualBuddyManagedPreferences.serviceTunnelPolicy(preferences: preferences)
        observations = VirtualBuddyManagedPreferences.observeServiceTunnelPolicy(preferences: preferences) { [weak self] in
            self?.refresh()
        }
    }

    public func refresh() {
        let current = VirtualBuddyManagedPreferences.serviceTunnelPolicy(preferences: preferences)
        guard current != policy else { return }
        policy = current
        VirtualBuddyManagedPreferences.logger.notice("The service tunnel policy changed")
        onChange?(current)
    }
}
