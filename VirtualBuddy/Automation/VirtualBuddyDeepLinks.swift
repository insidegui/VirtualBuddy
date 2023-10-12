import Foundation
import URLQueryItemCoder
import DeepLinkSecurity
import OSLog
import VirtualCore

private final class DeepLinkAuthUIPresenter: DeepLinkAuthUI {
    func presentDeepLinkAuth(for request: OpenDeepLinkRequest) async throws -> DeepLinkClientAuthorization {
        try await DeepLinkAuthPanel.run(for: request)
    }
}

struct OpenVMParameters: Codable {
    var name: String
}

struct BootVMParameters: Codable {
    var name: String
}

struct StopVMParameters: Codable {
    var name: String
}

enum DeepLinkAction  {
    case open(OpenVMParameters)
    case boot(BootVMParameters)
    case stop(StopVMParameters)
}

extension DeepLinkAction {
    init(_ url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure("Invalid URL: failed to construct URLComponents")
        }
        guard let host = components.host else {
            throw Failure("Invalid URL: missing host")
        }

        switch host {
        case "open":
            let params = try Self.decodeParameters(OpenVMParameters.self, from: components)
            self = .open(params)
        case "boot":
            let params = try Self.decodeParameters(BootVMParameters.self, from: components)
            self = .boot(params)
        case "stop":
            let params = try Self.decodeParameters(StopVMParameters.self, from: components)
            self = .stop(params)
        default:
            throw Failure("Unrecognized URL action \"\(host)\"")
        }
    }

    private static func decodeParameters<T>(_ type: T.Type, from components: URLComponents) throws -> T where T: Decodable {
        let items = components.queryItems ?? []
        return try URLQueryItemDecoder.deepLink.decode(type, from: items)
    }
}

private extension URLQueryItemDecoder {
    static let deepLink = URLQueryItemDecoder()
}

final class DeepLinkHandler {

    private lazy var logger = Logger(subsystem: kShellAppSubsystem, category: String(describing: Self.self))

    static let shared = DeepLinkHandler()

    private init() { }

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
    }

}
