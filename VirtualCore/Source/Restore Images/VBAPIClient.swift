//
//  VBAPIClient.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation

public final class VBAPIClient {

    public enum GuestType {
        case macOS
        case Linux

        var path: String {
            switch self {
            case .macOS:
                return "/restore/mac"
            case .Linux:
                return "/restore/linux"
            }
        }
    }

    public struct Environment: Hashable {
        public var baseURL: URL
        public var apiKey: String

        #if DEBUG
        public static let local = Environment(
            baseURL: URL(string: "https://virtualbuddy.ngrok.io")!,
            apiKey: "15A25D48-4A34-4EE4-A293-C22B0DE1B54E"
        )

        public static let development = Environment(
            baseURL: URL(string: "https://virtualbuddy-api-dev.bestbuddyapps3496.workers.dev")!,
            apiKey: "15A25D48-4A34-4EE4-A293-C22B0DE1B54E"
        )
        #endif

        public static let production = Environment(
            baseURL: URL(string: "https://api.virtualbuddy.app")!,
            apiKey: "15A25D48-4A34-4EE4-A293-C22B0DE1B54E"
        )

        public static var current: Environment {
            #if DEBUG
            if let override = UserDefaults.standard.string(forKey: "VBAPIEnvironment") {
                if override == "development" {
                    return .development
                } else if override == "local" {
                    return .local
                } else {
                    assertionFailure("Unknown API environment: \(override)")
                    return .production
                }
            } else {
                return .production
            }
            #else
            return .production
            #endif
        }
    }

    public let environment: Environment

    public init(environment: Environment = .current) {
        self.environment = environment
    }

    private func request(for endpoint: String) -> URLRequest {
        let url = environment.baseURL
            .appendingPathComponent(endpoint)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        components.queryItems = [
            URLQueryItem(name: "apiKey", value: environment.apiKey)
        ]

        return URLRequest(url: components.url!)
    }

    @MainActor
    public func fetchRestoreImages(for guest: GuestType) async throws -> [VBRestoreImageInfo] {
        let req = request(for: guest.path)

        let (data, res) = try await URLSession.shared.data(for: req)

        let code = (res as! HTTPURLResponse).statusCode

        guard code == 200 else {
            throw Failure("HTTP \(code)")
        }

        let response = try JSONDecoder().decode(VBRestoreImagesResponse.self, from: data)

        return response.images
    }

}
