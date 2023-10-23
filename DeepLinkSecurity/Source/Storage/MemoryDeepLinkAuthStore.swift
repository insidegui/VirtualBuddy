import Foundation
import OSLog

/// A very basic store that uses an in-memory dictionary and is destroyed when the app terminates. Useful for testing.
public final actor MemoryDeepLinkAuthStore: DeepLinkAuthStore {

    private lazy var logger = Logger.deepLinkLogger(for: Self.self)

    private var authorizationByClientRequirement = [String: DeepLinkClientAuthorization]()

    public init() { }

    public func authorization(for client: DeepLinkClient) async -> DeepLinkClientAuthorization {
        if let result = authorizationByClientRequirement[client.designatedRequirement] {
            logger.debug("Found existing authorization \(result) for \(client.designatedRequirement)")
            return result
        } else {
            logger.debug("No authorization in store for \(client.designatedRequirement), returning undetermined")
            return .undetermined
        }
    }

    public func setAuthorization(_ authorization: DeepLinkClientAuthorization, for client: DeepLinkClient) async throws {
        logger.debug("Setting authorization \(authorization) for \(client.designatedRequirement)")
        
        authorizationByClientRequirement[client.designatedRequirement] = authorization
    }

}
