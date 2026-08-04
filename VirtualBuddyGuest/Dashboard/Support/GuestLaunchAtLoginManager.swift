import Foundation
import ServiceManagement
import OSLog

final class GuestLaunchAtLoginManager: ObservableObject {

    private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Self.self))

    var isLaunchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async throws {
        logger.debug("Set launch at login enabled: \(enabled, privacy: .public)")

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }

        await MainActor.run { objectWillChange.send() }
    }

    private var hasAutoEnabledMainAppService: Bool {
        get { UserDefaults.standard.bool(forKey: #function) }
        set {
            UserDefaults.standard.set(newValue, forKey: #function)
            UserDefaults.standard.synchronize()
        }
    }

    func autoEnableIfNeeded() {
        unregisterLegacyLoginItemIfNeeded()

        guard !hasAutoEnabledMainAppService else { return }
        hasAutoEnabledMainAppService = true

        logger.notice("Attempting to auto-enable launch at login")

        Task {
            do {
                try await setLaunchAtLoginEnabled(true)

                logger.notice("Successfully auto-enabled launch at login")
            } catch {
                logger.error("Failed to auto-enable launch at login: \(error, privacy: .public)")
            }
        }
    }

}

private extension GuestLaunchAtLoginManager {
    func unregisterLegacyLoginItemIfNeeded() {
        /// Try to unregister regardless of the helper status since it's possible for it to not report enabled but still show up in System Settings.
        do {
            try SMAppService.legacyGuestHelper.unregister()
        } catch {
            guard SMAppService.legacyGuestHelper.status == .enabled else { return }

            logger.fault("Error unregistering legacy guest helper login item - \(error, privacy: .public)")
        }
    }
}

private extension SMAppService {
    static let legacyGuestHelper = SMAppService.loginItem(identifier: kLegacyGuestAppLaunchAtLoginHelperBundleID)
}
