//
//  VBAPIClient.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation
import OSLog

public final class VBAPIClient {

    private let logger = Logger(for: VBAPIClient.self)

    public struct Environment: Hashable {
        public var baseURL: URL
        public var apiKey: String

        #if DEBUG
        public static let local = Environment(
            baseURL: URL(string: "https://virtualbuddy.ngrok.io/v2")!,
            apiKey: "15A25D48-4A34-4EE4-A293-C22B0DE1B54E"
        )

        public static let development = Environment(
            baseURL: URL(string: "https://virtualbuddy-api-dev.bestbuddyapps3496.workers.dev/v2")!,
            apiKey: "15A25D48-4A34-4EE4-A293-C22B0DE1B54E"
        )
        #endif

        public static let production = Environment(
            baseURL: URL(string: "https://api.virtualbuddy.app/v2")!,
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

    private static let decoder = JSONDecoder()

    @MainActor
    public func fetchRestoreImages(for guest: VBGuestType) async throws -> SoftwareCatalog {
        let catalog = try await performCatalogFetch(for: guest)

        SoftwareCatalog.setCurrent(catalog, for: guest)

        return catalog
    }

    @MainActor
    func performCatalogFetch(for guest: VBGuestType) async throws -> SoftwareCatalog {
        #if DEBUG
        guard !ProcessInfo.isSwiftUIPreview, !UserDefaults.standard.bool(forKey: "VBForceBuiltInSoftwareCatalog") else {
            logger.debug("Forcing built-in catalog")
            return try Self.fetchBuiltInCatalog(for: guest)
        }
        #endif

        do {
            let remoteCatalog = try await fetchRemoteCatalog(for: guest)

            logger.debug("Fetched remote catalog with \(remoteCatalog.restoreImages.count, privacy: .public) restore images")

            return remoteCatalog
        } catch {
            logger.error("Remote catalog fetch failed: \(error, privacy: .public), using local fallback")

            do {
                let builtInCatalog = try Self.fetchBuiltInCatalog(for: guest)

                logger.debug("Fetched built-in catalog with \(builtInCatalog.restoreImages.count, privacy: .public) restore images")

                return builtInCatalog
            } catch {
                logger.fault("Built-in catalog load failed: \(error, privacy: .public)")
                assertionFailure("Built-in catalog load failed: \(error)")
                throw error
            }
        }
    }

    func fetchRemoteCatalog(for guest: VBGuestType) async throws -> SoftwareCatalog {
        let req = request(for: guest.restoreImagesAPIPath)

        logger.debug("Fetching remote catalog from \(req.url?.host() ?? "<nil>")")

        let (data, res) = try await URLSession.shared.data(for: req)

        let code = (res as! HTTPURLResponse).statusCode

        guard code == 200 else {
            throw Failure("HTTP \(code)")
        }

        let response = try Self.decoder.decode(SoftwareCatalog.self, from: data)

        return response
    }

    static func fetchBuiltInCatalog(for guest: VBGuestType) throws -> SoftwareCatalog {
        let fileName = switch guest {
        case .mac:
            "ipsws_v2"
        case .linux:
            "linux_v2"
        }

        guard let url = Bundle.virtualCore.url(forResource: fileName, withExtension: "json", subdirectory: "SoftwareCatalog") else {
            throw Failure("\(fileName) not found in VirtualCore SoftwareCatalog resources")
        }

        let data = try Data(contentsOf: url)

        return try decoder.decode(SoftwareCatalog.self, from: data)
    }

}

private extension VBGuestType {
    var restoreImagesAPIPath: String {
        switch self {
        case .mac:
            return "/restore/mac"
        case .linux:
            return "/restore/linux"
        }
    }
}
