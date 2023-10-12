import Cocoa
import OSLog

public final class DeepLinkSentinel {
    private lazy var logger = Logger.deepLinkLogger(for: Self.self)

    public let authUI: DeepLinkAuthUI
    public let authStore: DeepLinkAuthStore
    public let managementStore: DeepLinkManagementStore

    public init(authUI: DeepLinkAuthUI, authStore: DeepLinkAuthStore, managementStore: DeepLinkManagementStore) {
        self.authUI = authUI
        self.authStore = authStore
        self.managementStore = managementStore
    }

    /// Sets the sentinel as the handler for URL scheme Apple Events.
    public func installAppleEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(DeepLinkSentinel.handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    /// Delivers open URL events once they've been authenticated.
    /// Open URL requests that fail authentication are not delivered.
    public private(set) lazy var openURL: AsyncStream<URL> = {
        AsyncStream { [weak self] continuation in
            self?.onOpenURL = { url in
                continuation.yield(url)
            }
        }
    }()

    private var onOpenURL: (URL) -> Void = { _ in }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        logger.debug(#function)

        guard let urlStr = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else {
            logger.fault("Failed to get string from URL open event")
            return
        }

        logger.debug("Handling URL \(urlStr)")

        guard let tokenDescriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.copy() as? NSAppleEventDescriptor else {
            logger.error("Missing Apple Event sender audit token in URL event")
            return
        }

        guard let url = URL(string: urlStr) else {
            logger.error("Invalid deep link URL: \"\(urlStr)\"")
            return
        }

        Task {
            await authenticate(descriptor: tokenDescriptor, url: url)
        }
    }

    func storeDescriptor(_ descriptor: DeepLinkClientDescriptor, with authorization: DeepLinkClientAuthorization = .undetermined) async {
        do {
            var updatedDescriptor = descriptor
            updatedDescriptor.authorization = authorization

            try await managementStore.insert(updatedDescriptor)
        } catch {
            logger.warning("Failed to store management descriptor: \(error, privacy: .public)")
        }
    }

    func setAuthorization(_ result: DeepLinkClientAuthorization, for client: DeepLinkClient, descriptor: DeepLinkClientDescriptor) async {
        do {
            try await authStore.setAuthorization(result, for: client)

            /// Update the client management descriptor with the new authorization.
            await storeDescriptor(descriptor, with: result)
        } catch {
            logger.warning("Failed to store authorization decision: \(error, privacy: .public)")
        }
    }

    public func setAuthorization(_ result: DeepLinkClientAuthorization, for descriptor: DeepLinkClientDescriptor) async throws {
        let client = try DeepLinkClient(url: descriptor.url)

        try await authStore.setAuthorization(result, for: client)

        /// Update the client management descriptor with the new authorization.
        await storeDescriptor(descriptor, with: result)
    }

    private func authenticate(descriptor: NSAppleEventDescriptor, url: URL) async {
        do {
            let client = try DeepLinkClient(auditTokenDescriptor: descriptor)

            let clientDescriptor = DeepLinkClientDescriptor(client: client)

            do {
                /// Store an initial entry for the client descriptor if it doesn't exist yet.
                let descriptorExists = await managementStore.hasDescriptor(with: clientDescriptor.id)
                if !descriptorExists {
                    try await managementStore.insert(clientDescriptor)
                }
            } catch {
                logger.warning("Failed to store management descriptor before auth: \(error, privacy: .public)")
            }

            let request = OpenDeepLinkRequest(url: url, client: clientDescriptor)

            do {
                var authorization = await existingAuthorization(for: client)

                switch authorization {
                case .undetermined:
                    logger.debug("No existing authorization for \(client.designatedRequirement), prompting")

                    authorization = try await authUI.presentDeepLinkAuth(for: request)

                    guard authorization != .undetermined else {
                        logger.warning("Auth UI ended with undetermined authorization, denying current request without modifying auth store")
                        return
                    }

                    await setAuthorization(authorization, for: client, descriptor: clientDescriptor)
                case .authorized:
                    logger.debug("Got existing client authorization for \(client.designatedRequirement)")
                case .denied:
                    logger.warning("Denying open URL: client authorization denied for \(client.designatedRequirement)")
                    return
                }

                /// Just being extra paranoid here.
                guard authorization != .denied else { return }

                logger.notice("Successfully authenticated deep link request for opening \(url)")

                await MainActor.run {
                    onOpenURL(url)
                }
            } catch {
                logger.error("Deep link authentication failed: \(error, privacy: .public)")
            }
        } catch {
            logger.error("Failed to get client information: \(error, privacy: .public)")
        }
    }

    private func existingAuthorization(for client: DeepLinkClient) async -> DeepLinkClientAuthorization {
        let auth = await authStore.authorization(for: client)

        guard auth == .authorized else { return auth }

        do {
            try await client.validate()

            return .authorized
        } catch {
            logger.warning("Client signature validated for \(client.designatedRequirement), prompting again. Error: \(error, privacy: .public)")

            return .undetermined
        }
    }
}

extension NSAppleEventDescriptor: @unchecked Sendable { }
