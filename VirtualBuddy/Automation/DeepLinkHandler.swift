import SwiftUI
import VirtualCore
import VirtualUI
import OSLog
import DeepLinkSecurity

final class DeepLinkHandler {

    private let settingsContainer: VBSettingsContainer
    private let updateController: SoftwareUpdateController
    private let library: VMLibraryController
    private let sessionManager: VirtualMachineSessionUIManager

    static var shared: DeepLinkHandler {
        guard let _shared else {
            fatalError("Attempting to access DeepLinkHandler instance before calling bootstrap()")
        }
        return _shared
    }

    private static var _shared: DeepLinkHandler!

    @MainActor
    static func bootstrap() {
        DeepLinkHandler._shared = DeepLinkHandler()
        DeepLinkHandler.shared.install()
    }

    @MainActor
    private init() {
        self.settingsContainer = VBSettingsContainer.current
        self.updateController = SoftwareUpdateController.shared
        self.library = VMLibraryController.shared
        self.sessionManager = VirtualMachineSessionUIManager.shared
    }

    private lazy var logger = Logger(subsystem: kShellAppSubsystem, category: String(describing: Self.self))

    private let namespace = "VirtualBuddy"
    private let keyID = "c3bfea24ee1ca95700a4e56d73097aac"

    private(set) lazy var sentinel = DeepLinkSentinel(
        authUI: DeepLinkAuthUIPresenter(),
        authStore: KeychainDeepLinkAuthStore(namespace: namespace, keyID: keyID),
        managementStore: UserDefaultsDeepLinkManagementStore()
    )

    private let openWindow = OpenCocoaWindowAction.default

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
                await execute(action)
            }
        }
    }

    @MainActor
    private func execute(_ action: DeepLinkAction) {
        do {
            switch action {
            case .open(let params):
                try openVM(named: params.name, options: nil)
            case .boot(let params):
                var effectiveOptions = params.options ?? VMSessionOptions.default
                effectiveOptions.autoBoot = true
                try openVM(named: params.name, options: effectiveOptions)
            case .stop(let params):
                try stopVM(named: params.name)
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @MainActor
    private func openVM(named name: String, options: VMSessionOptions?) throws {
        let vm = try getVM(named: name)

        openWindow(id: vm.id) {
            VirtualMachineSessionView(controller: VMController(with: vm, options: options), ui: VirtualMachineSessionUI(with: vm))
                .environmentObject(self.library)
                .environmentObject(self.sessionManager)
        }
    }

    private func stopVM(named name: String) throws {

    }

    @MainActor
    private func getVM(named name: String) throws -> VBVirtualMachine {
        guard let vm = library.virtualMachine(named: name) else {
            throw Failure("Couldn't find a virtual machine with the name \"\(name)\".")
        }
        return vm
    }
}

private final class DeepLinkAuthUIPresenter: DeepLinkAuthUI {
    func presentDeepLinkAuth(for request: OpenDeepLinkRequest) async throws -> DeepLinkClientAuthorization {
        try await DeepLinkAuthPanel.run(for: request)
    }
}
