import Foundation
import ManagedPreferencesKit
import Observation
import OSLog
import VirtualWormhole

enum SecuritySettingsLog {
    static let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "SecuritySettings")
}

public extension VirtualBuddyManagedPreferences {
    /// The least review the organization accepts for service tunnels, or `nil` when it doesn't set one.
    ///
    /// The preference only ever adds review, so a value that can't be read counts as asking for all of it.
    static func serviceTunnelMinimumReviewLevel(preferences: Reader = schema.reader()) -> ServiceTunnelSecurityLevel? {
        serviceTunnelMinimumReviewLevel(preferences.resolve(.serviceTunnelMinimumReviewLevel))
    }

    /// The same, for a value of the preference that was already looked up.
    static func serviceTunnelMinimumReviewLevel(_ resolution: ManagedPreferenceResolution<VirtualBuddyManagedPreferences, String>) -> ServiceTunnelSecurityLevel? {
        guard resolution.rawValue != nil else { return nil }
        guard let level = resolution.value.flatMap(ServiceTunnelSecurityLevel.init(rawValue:)) else {
            logger.error("ServiceTunnelMinimumReviewLevel is not one of its options. Every service tunnel change is reviewed.")
            return .strictest
        }
        return level
    }
}

/// The review that service tunnels get on this host, as the code that reads and approves tunnel settings needs it.
struct ServiceTunnelSecurity {
    var level: () -> ServiceTunnelSecurityLevel
    var isRemembered: (ServiceTunnelIdentity) -> Bool
    var remember: ([ServiceTunnelIdentity]) throws -> Void

    /// The user's setting, raised to whatever the organization requires. Both are read when they're applied.
    static var current: Self { Self(storage: .keychain) { VirtualBuddyManagedPreferences.serviceTunnelMinimumReviewLevel() } }

    init(
        level: @escaping () -> ServiceTunnelSecurityLevel,
        isRemembered: @escaping (ServiceTunnelIdentity) -> Bool,
        remember: @escaping ([ServiceTunnelIdentity]) throws -> Void
    ) {
        self.level = level
        self.isRemembered = isRemembered
        self.remember = remember
    }

    init(storage: SecuritySettingsStorage, minimumLevel: @escaping () -> ServiceTunnelSecurityLevel?) {
        self.init(
            level: { max(storage.tunnelLevel(), minimumLevel() ?? .reviewNone) },
            isRemembered: { identity in
                do { return try storage.isRemembered(identity) }
                catch {
                    SecuritySettingsLog.logger.error("Unable to look up a reviewed service tunnel, so it's reviewed again: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            },
            remember: { try storage.remember($0) }
        )
    }
}

/// Keeps track of the service tunnel review level while the user or the organization changes it.
@MainActor @Observable
public final class ServiceTunnelSecurityMonitor {
    public private(set) var level: ServiceTunnelSecurityLevel

    /// Called when what tunnels may run without review could be different: the level changed, or reviewed tunnels were forgotten.
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let security: ServiceTunnelSecurity
    @ObservationIgnored private var observations: [Any] = []

    public convenience init() {
        self.init(security: .current, session: .shared, preferences: VirtualBuddyManagedPreferences.schema.reader())
    }

    init(security: ServiceTunnelSecurity, session: SecuritySettingsSession, preferences: VirtualBuddyManagedPreferences.Reader) {
        self.security = security
        level = security.level()
        observations.append(session.observeChanges { [weak self] in self?.refresh() })
        if let observation = preferences.observeChanges(for: .serviceTunnelMinimumReviewLevel, handler: { [weak self] in self?.refresh() }) {
            observations.append(observation)
        }
    }

    private func refresh() {
        let current = security.level()
        if current != level {
            level = current
            SecuritySettingsLog.logger.notice("The service tunnel review level is now \(current.rawValue, privacy: .public)")
        }
        onChange?()
    }
}
