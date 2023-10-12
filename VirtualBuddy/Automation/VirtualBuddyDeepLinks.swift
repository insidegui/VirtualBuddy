import Foundation
import URLQueryItemCoder
import DeepLinkSecurity
import OSLog
import VirtualCore

struct OpenVMParameters: Codable {
    var name: String
}

struct BootVMParameters: Codable {
    var name: String
    var options: VMSessionOptions?
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
