import SwiftUI
import VirtualCore
import VirtualUI
import OSLog
import DeepLinkSecurity

typealias WindowUpdatingClosure = (_ perform: () -> Void) -> Void

extension Notification.Name {
    /// Notification sent from ``DeepLinkHandler`` when it wants the SwiftUI app to open the library window.
    static let openVirtualBuddyLibraryWindow = Notification.Name("codes.rambo.VirtualBuddy.OpenLibraryWindow")
}

final class DeepLinkHandler {

    private let settingsContainer: VBSettingsContainer
    private let updateController: SoftwareUpdateController
    private let library: VMLibraryController
    private let sessionManager: VirtualMachineSessionUIManager

    let runner: ActionRunner

    static var shared: DeepLinkHandler {
        guard let _shared else {
            fatalError("Attempting to access DeepLinkHandler instance before calling bootstrap()")
        }
        return _shared
    }

    private static var _shared: DeepLinkHandler!

    @MainActor
    static func bootstrap(library: VMLibraryController) {
        DeepLinkHandler._shared = DeepLinkHandler(library: library)
        DeepLinkHandler.shared.install()
    }

    @MainActor
    private init(library: VMLibraryController) {
        self.settingsContainer = VBSettingsContainer.current
        self.updateController = SoftwareUpdateController.shared
        self.library = library
        self.sessionManager = VirtualMachineSessionUIManager.shared
        self.runner = ActionRunner(library: library, sessionManager: sessionManager)
    }

    private lazy var logger = Logger(subsystem: kShellAppSubsystem, category: String(describing: Self.self))

    private let namespace = "VirtualBuddy"
    private let keyID = "c3bfea24ee1ca95700a4e56d73097aac"

    private(set) lazy var sentinel: DeepLinkSentinel = {
        let store = KeychainDeepLinkStore(
            service: "codes.rambo.VirtualBuddy.deep-links",
            legacy: LegacyDeepLinkStores(
                authStore: KeychainDeepLinkAuthStore(namespace: namespace, keyID: keyID),
                managementStore: UserDefaultsDeepLinkManagementStore()
            )
        )
        return DeepLinkSentinel(
            authUI: DeepLinkAuthUIPresenter(),
            authStore: store,
            managementStore: store,
            canManageClients: { SecuritySettingsSession.shared.isUnlocked }
        )
    }()

    func actions() -> AsyncCompactMapSequence<AsyncStream<URL>, DeepLinkAction> {
        sentinel.openURL.compactMap { url in
            do {
                let action = try DeepLinkAction(url)

                self.logger.debug("Action: \(String(describing: action))")

                return action
            } catch {
                self.logger.error("Error processing deep link URL \"\(url)\": \(error, privacy: .public)")
                return nil
            }
        }
    }

    func install() {
        sentinel.installAppleEventHandler()

        Task {
            for await action in DeepLinkHandler.shared.actions() {
                await runner.run(action)
            }
        }
    }

    @MainActor
    final class ActionRunner {
        let automation: VMAutomationService

        init(library: VMLibraryController, sessionManager: VirtualMachineSessionUIManager) {
            self.automation = VMAutomationService(library: library, sessionManager: sessionManager)
        }

        func run(_ action: DeepLinkAction) async {
            do {
                switch action {
                case .library:
                    NotificationCenter.default.post(name: .openVirtualBuddyLibraryWindow, object: action)
                case .open(let params):
                    try automation.open(automation.virtualMachine(named: params.name), options: nil)
                case .boot(let params):
                    var effectiveOptions = params.options ?? VMSessionOptions.default
                    effectiveOptions.autoBoot = true
                    try automation.open(automation.virtualMachine(named: params.name), options: effectiveOptions)
                case .stop(let params):
                    try await automation.stop(named: params.name)
                }
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}

private final class DeepLinkAuthUIPresenter: DeepLinkAuthUI {
    func presentDeepLinkAuth(for request: OpenDeepLinkRequest) async throws -> DeepLinkClientAuthorization {
        try await DeepLinkAuthPanel.run(for: request)
    }
}

extension String {
    var wrappedInSmartQuotes: String { "“\(self)”" }
}
