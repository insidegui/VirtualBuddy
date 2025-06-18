import SwiftUI
import CryptoKit
import VirtualCore
import OSLog

struct RemoteImage: View {
    var url: URL
    var blurHash: String?
    var blurHashSize: CGSize
    var loader: RemoteImageLoader

    init(url: URL, blurHash: String? = nil, blurHashSize: CGSize = .vbBlurHashSize, loader: RemoteImageLoader = .default) {
        self.url = url
        self.blurHash = blurHash
        self.blurHashSize = blurHashSize
        self.loader = loader
        self._nsImage = .init(initialValue: loader.cachedImage(for: url))
    }

    @State private var nsImage: NSImage?

    var body: some View {
        ZStack {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
            } else {
                if let blurHash {
                    Image(blurHash: blurHash, size: blurHashSize)
                        .resizable()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                }
            }
        }
        .task(id: url) {
            nsImage = await loader.load(from: url)
        }
    }
}

final class RemoteImageLoader {
    private let logger = Logger(subsystem: "codes.rambo.RemoteImageLoader", category: "RemoteImageLoader")

    private let memoryCache = NSCache<NSString, NSImage>()

    static let `default` = RemoteImageLoader()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config)
    }()

    func load(from remoteURL: URL) async -> NSImage? {
        guard !remoteURL.isFileURL else {
            return NSImage(contentsOf: remoteURL)
        }
        
        if let cached = cachedImage(for: remoteURL) {
            return cached
        }

        do {
            let (fileURL, response) = try await session.download(from: remoteURL)

            let stagedFileURL = try fileURL.temporaryCopy(usingPathExtensionFrom: remoteURL)

            let code = (response as? HTTPURLResponse)?.statusCode ?? -1

            guard code == 200 else {
                throw Failure("HTTP \(code)")
            }

            guard let image = NSImage(contentsOf: stagedFileURL) else {
                throw Failure("Image initialization failed")
            }

            store(image: image, localFileURL: stagedFileURL, for: remoteURL)

            return image
        } catch {
            logger.warning("Image download failed: \(error, privacy: .public). Image URL: \(remoteURL.absoluteString)")

            return nil
        }
    }

    func cachedImage(for url: URL) -> NSImage? {
        let key = cacheKey(for: url)

        if let memImage = memoryCache.object(forKey: key as NSString) {
            return memImage
        } else {
            let storageURL = diskURL(for: key)

            guard FileManager.default.fileExists(atPath: storageURL.path) else {
                return nil
            }

            return NSImage(contentsOf: storageURL)
        }
    }

    private func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined() + ".\(url.pathExtension)"
    }

    private func diskURL(for key: String) -> URL {
        do {
            let baseURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(Bundle.main.bundleURL.deletingPathExtension().lastPathComponent)
                .appendingPathComponent("ImageCache")

            if !FileManager.default.fileExists(atPath: baseURL.path) {
                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            }

            return baseURL.appendingPathComponent(key)
        } catch {
            assertionFailure("Failed to create cache directory: \(error)")
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    private func store(image: NSImage, localFileURL: URL, for url: URL) {
        let key = cacheKey(for: url)

        memoryCache.setObject(image, forKey: key as NSString)

        let storageURL = diskURL(for: key)

        do {
            try FileManager.default.copyItem(at: localFileURL, to: storageURL)
        } catch {
            logger.error("Cache write failed: \(error, privacy: .public)")

            assertionFailure("Cache write failed: \(error)")
        }
    }
}

private extension URL {
    func temporaryCopy(usingPathExtensionFrom other: URL) throws -> URL {
        let fileName = deletingPathExtension().lastPathComponent
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(fileName)
            .appendingPathExtension(other.pathExtension)
        try FileManager.default.copyItem(at: self, to: tempURL)
        return tempURL
    }
}
