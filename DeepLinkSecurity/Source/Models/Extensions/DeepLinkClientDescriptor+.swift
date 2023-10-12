import Cocoa

public extension DeepLinkClientDescriptor {
    init(client: DeepLinkClient, authorization: DeepLinkClientAuthorization = .undetermined) {
        self.init(clientID: client.id, clientURL: client.url, authorization: authorization)
    }

    init(clientID: DeepLinkClient.ID, clientURL: URL, authorization: DeepLinkClientAuthorization = .undetermined) {
        let bundle = Bundle(url: clientURL)

        self.init(
            id: clientID,
            url: clientURL,
            bundleIdentifier: bundle.flatMap(\.bundleIdentifier),
            displayName: bundle.flatMap(\.bestEffortAppName) ?? clientURL.fileNameWithoutExtension,
            icon: Icon(clientURL: clientURL),
            authorization: authorization,
            isValid: FileManager.default.fileExists(atPath: clientURL.path)
        )
    }

    /// Checks if the descriptor's client is still present at its original filesystem location,
    /// attempting to update the client if it's been moved or deleted.
    func resolved() -> DeepLinkClientDescriptor {
        guard let bundleIdentifier else { return self }
        guard !FileManager.default.fileExists(atPath: url.path) else { return self }

        guard let updatedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return self.invalidated() }

        return DeepLinkClientDescriptor(clientID: id, clientURL: updatedURL, authorization: authorization)
    }

    func invalidated() -> DeepLinkClientDescriptor {
        var mSelf = self
        mSelf.isValid = false
        return mSelf
    }

    func withAuthorization(_ authorization: DeepLinkClientAuthorization) -> DeepLinkClientDescriptor {
        var mSelf = self
        mSelf.authorization = authorization
        return mSelf
    }
}

public extension DeepLinkClientDescriptor.Icon {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        let image = NSImage(data: data) ?? NSWorkspace.shared.icon(for: .application)

        self.init(image: image)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        guard let png = image.pngData() else {
            throw EncodingError.invalidValue(0, .init(codingPath: [], debugDescription: "Failed to get icon PNG data"))
        }

        try container.encode(png)
    }
}

private extension DeepLinkClientDescriptor.Icon {
    init(clientURL: URL) {
        let image: NSImage
        if FileManager.default.fileExists(atPath: clientURL.path) {
            image = NSWorkspace.shared.icon(forFile: clientURL.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        image.size = NSSize(width: 64, height: 64)
        self.init(image: image)
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }

        return png
    }
}

private extension Bundle {
    var bestEffortAppName: String? {
        guard let info = infoDictionary else { return bundleURL.fileNameWithoutExtension }

        return info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? bundleURL.fileNameWithoutExtension
    }
}

private extension URL {
    var fileNameWithoutExtension: String { deletingPathExtension().lastPathComponent }
}
