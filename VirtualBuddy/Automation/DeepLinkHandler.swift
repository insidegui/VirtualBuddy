import SwiftUI
import VirtualCore
import VirtualUI
import OSLog
import DeepLinkSecurity

typealias WindowUpdatingClosure = (_ perform: () -> Void) -> Void

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
        self.runner = ActionRunner(
            settingsContainer: settingsContainer,
            updateController: updateController,
            library: library,
            sessionManager: sessionManager
        )
    }

    private lazy var logger = Logger(subsystem: kShellAppSubsystem, category: String(describing: Self.self))

    private let namespace = "VirtualBuddy"
    private let keyID = "c3bfea24ee1ca95700a4e56d73097aac"

    private(set) lazy var sentinel = DeepLinkSentinel(
        authUI: DeepLinkAuthUIPresenter(),
        authStore: KeychainDeepLinkAuthStore(namespace: namespace, keyID: keyID),
        managementStore: UserDefaultsDeepLinkManagementStore()
    )

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
        private let settingsContainer: VBSettingsContainer
        private let updateController: SoftwareUpdateController
        private let library: VMLibraryController
        private let sessionManager: VirtualMachineSessionUIManager
        private let openWindow = OpenCocoaWindowAction.default

        init(settingsContainer: VBSettingsContainer,
             updateController: SoftwareUpdateController,
             library: VMLibraryController,
             sessionManager: VirtualMachineSessionUIManager)
        {
            self.settingsContainer = settingsContainer
            self.updateController = updateController
            self.library = library
            self.sessionManager = sessionManager
        }

        func run(_ action: DeepLinkAction) async {
            do {
                switch action {
                case .open(let params):
                    try openVM(named: params.name, options: nil)
                case .boot(let params):
                    var effectiveOptions = params.options ?? VMSessionOptions.default
                    effectiveOptions.autoBoot = true
                    try openVM(named: params.name, options: effectiveOptions)
                case .stop(let params):
                    try await stopVM(named: params.name)
                }
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }

        func openVM(named name: String, options: VMSessionOptions?) throws {
            let vm = try getVM(named: name)

            sessionManager.launch(vm, library: library, options: options)
        }

        func stopVM(named name: String) async throws {
            let controller = try getController(forVMNamed: name)

            switch controller.state {
            case .idle, .stopped:
                throw Failure("Can't stop virtual machine \(name.wrappedInSmartQuotes) because it's not running.")
            default:
                try await controller.stop()
            }
        }

        func getVM(named name: String) throws -> VBVirtualMachine {
            guard let vm = library.virtualMachine(named: name) else {
                throw Failure("Couldn't find a virtual machine with the name \(name.wrappedInSmartQuotes).")
            }
            return vm
        }

        func getController(forVMNamed name: String) throws -> VMController {
            let vm = try getVM(named: name)
            guard let controller = library.activeController(for: vm.id) else {
                throw Failure("Couldn't find active instance of virtual machine with the name \(name.wrappedInSmartQuotes).")
            }
            return controller
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
