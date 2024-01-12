import SwiftUI

public protocol DeepLinkAuthUI: AnyObject {
    /// Return ``DeepLinkClientAuthorization/authorized`` if the user has allowed the client to open deep links in the app.
    /// 
    /// If this method throws, then the auth store is not modified and the user will be prompted again the next time the same client
    /// attempts to open a deep link in the app.
    ///
    /// If this method returns ``DeepLinkClientAuthorization/denied``, then the auth store will be modified and future
    /// requests from the same client will be rejected without a prompt.
    @MainActor
    func presentDeepLinkAuth(for request: OpenDeepLinkRequest) async throws -> DeepLinkClientAuthorization
}
