import Foundation
import ManagedPreferencesKit
import Observation

/// Whether the `vbctl` command-line tool may control the app.
///
/// The user turns this on in the Security settings, and the organization managing the Mac can keep it off.
/// The tool is the app's own executable, so it reads the same setting the app does.
public enum CommandLineAccess {
    /// Read when it's applied, so that enforcement never depends on having noticed a change.
    public static var isEnabled: Bool { isEnabled(storage: .keychain, preferences: VirtualBuddyManagedPreferences.schema.reader()) }

    public static var isDisabledByOrganization: Bool {
        VirtualBuddyManagedPreferences.schema.reader().value(for: .disableCommandLineAccess, default: false)
    }

    static func isEnabled(storage: SecuritySettingsStorage, preferences: VirtualBuddyManagedPreferences.Reader) -> Bool {
        !preferences.value(for: .disableCommandLineAccess, default: false) && storage.isCommandLineAccessEnabled()
    }

    public static func requireEnabled() throws {
        guard !isDisabledByOrganization else { throw Failure("Command-line access is disabled by your organization.") }
        guard isEnabled else { throw Failure("Command-line access is turned off. Enable it in VirtualBuddy Settings → Security.") }
    }
}

/// Keeps track of whether command-line access is on while the user or the organization changes it.
@MainActor @Observable
public final class CommandLineAccessMonitor {
    public private(set) var isEnabled: Bool

    @ObservationIgnored public var onChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private let resolve: () -> Bool
    @ObservationIgnored private var observations: [Any] = []

    public convenience init() {
        let preferences = VirtualBuddyManagedPreferences.schema.reader()
        self.init(session: .shared, preferences: preferences) { CommandLineAccess.isEnabled(storage: .keychain, preferences: preferences) }
    }

    init(session: SecuritySettingsSession, preferences: VirtualBuddyManagedPreferences.Reader, resolve: @escaping () -> Bool) {
        self.resolve = resolve
        isEnabled = resolve()
        observations.append(session.observeChanges { [weak self] in self?.refresh() })
        if let observation = preferences.observeChanges(for: .disableCommandLineAccess, handler: { [weak self] in self?.refresh() }) {
            observations.append(observation)
        }
    }

    private func refresh() {
        let current = resolve()
        guard current != isEnabled else { return }
        isEnabled = current
        SecuritySettingsLog.logger.notice("Command-line access is now \(current ? "on" : "off", privacy: .public)")
        onChange?(current)
    }
}
