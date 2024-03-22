import Foundation
import ServiceManagement
import OSLog

final class GuestLaunchAtLoginManager: ObservableObject {

    private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Self.self))

    var isLaunchAtLoginEnabled: Bool { SMAppService.guestHelper.status == .enabled }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async throws {
        logger.debug("Set launch at login enabled: \(enabled, privacy: .public)")

        if enabled {
            try SMAppService.guestHelper.register()
        } else {
            try await SMAppService.guestHelper.unregister()
        }

        await MainActor.run { objectWillChange.send() }
    }

    private var hasAutoEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: #function) }
        set {
            UserDefaults.standard.set(newValue, forKey: #function)
            UserDefaults.standard.synchronize()
        }
    }

    func autoEnableIfNeeded() {
        guard !hasAutoEnabled else { return }
        hasAutoEnabled = true

        logger.debug("Attempting to auto-enable launch at login")

        Task {
            do {
                try await setLaunchAtLoginEnabled(true)

                logger.debug("Successfully auto-enabled launch at login")
            } catch {
                logger.error("Failed to auto-enable launch at login: \(error, privacy: .public)")
            }
        }
    }

}

@available(macOS 13.0, *)
private extension SMAppService {
    static let guestHelper = SMAppService.loginItem(identifier: kGuestAppLaunchAtLoginHelperBundleID)
}
