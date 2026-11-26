import Foundation
import LocalAuthentication
import Observation

/// The only way to change the host's security settings.
///
/// Settings stay readable at all times, but changing one requires the user to have proven they're present
/// with Touch ID or their account password. The proof lasts until ``lock()``, which the settings window
/// calls when it goes away.
@MainActor @Observable
public final class SecuritySettingsSession {
    public static let shared = SecuritySettingsSession()

    public private(set) var isUnlocked = false
    public private(set) var tunnelLevel: ServiceTunnelSecurityLevel
    /// How many reviewed tunnels are remembered, or `nil` when the Keychain can't be read.
    public private(set) var rememberedTunnelCount: Int?
    /// Whether the user lets `vbctl` control the app. An organization can still keep it off, see ``CommandLineAccess``.
    public private(set) var isCommandLineAccessEnabled: Bool

    @ObservationIgnored private let storage: SecuritySettingsStorage
    @ObservationIgnored private let authenticate: @MainActor (_ reason: String) async throws -> Void
    @ObservationIgnored private var observers: [UUID: @MainActor () -> Void] = [:]

    public convenience init() {
        self.init(storage: .keychain, authenticate: Self.authenticateDeviceOwner)
    }

    init(storage: SecuritySettingsStorage, authenticate: @escaping @MainActor (_ reason: String) async throws -> Void) {
        self.storage = storage
        self.authenticate = authenticate
        tunnelLevel = storage.tunnelLevel()
        rememberedTunnelCount = try? storage.rememberedTunnelCount()
        isCommandLineAccessEnabled = storage.isCommandLineAccessEnabled()
    }

    #if DEBUG
    /// Keeps its settings in memory and unlocks without asking, for previews.
    public static func preview(commandLineAccess: Bool = false) -> SecuritySettingsSession {
        let storage = SecuritySettingsStorage.inMemory()
        try? storage.setCommandLineAccessEnabled(commandLineAccess)
        return SecuritySettingsSession(storage: storage, authenticate: { _ in })
    }
    #endif

    private static func authenticateDeviceOwner(reason: String) async throws {
        let context = LAContext()
        // Each unlock asks again rather than riding on a recent Touch ID match elsewhere.
        context.touchIDAuthenticationAllowableReuseDuration = 0
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    /// Asks the user to prove they're present. Throws when they cancel or can't.
    public func unlock() async throws {
        guard !isUnlocked else { return }
        try await authenticate("change security settings")
        isUnlocked = true
        reload()
    }

    public func lock() {
        isUnlocked = false
    }

    /// Reads the settings again, for showing what's saved right now.
    public func reload() {
        tunnelLevel = storage.tunnelLevel()
        rememberedTunnelCount = try? storage.rememberedTunnelCount()
        isCommandLineAccessEnabled = storage.isCommandLineAccessEnabled()
    }

    public func setCommandLineAccessEnabled(_ enabled: Bool) throws {
        try requireUnlocked()
        try storage.setCommandLineAccessEnabled(enabled)
        reload()
        notify()
    }

    public func setTunnelLevel(_ level: ServiceTunnelSecurityLevel) throws {
        try requireUnlocked()
        try storage.setTunnelLevel(level)
        reload()
        notify()
    }

    public func forgetRememberedTunnels() throws {
        try requireUnlocked()
        try storage.forgetTunnels()
        reload()
        notify()
    }

    private func requireUnlocked() throws {
        guard isUnlocked else { throw Failure("Unlock the security settings before changing them.") }
    }

    private func notify() {
        for observer in observers.values { observer() }
    }

    /// Calls the handler after a setting changed, for as long as the returned token is kept.
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> SecuritySettingsObservation {
        let id = UUID()
        observers[id] = handler
        return SecuritySettingsObservation { [weak self] in
            Task { @MainActor in self?.observers[id] = nil }
        }
    }
}

final class SecuritySettingsObservation: Sendable {
    private let cancel: @Sendable () -> Void

    init(cancel: @escaping @Sendable () -> Void) { self.cancel = cancel }

    deinit { cancel() }
}
