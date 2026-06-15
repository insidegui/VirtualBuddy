//
//  GuestAdditionsDiskImage.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/03/23.
//

import Foundation
import Virtualization
import CryptoKit
import UniformTypeIdentifiers
import OSLog
import Combine
import BuddyFoundation

public final class GuestAdditionsDiskImage: ObservableObject {

    private let logger: Logger

    public static let `default` = GuestAdditionsDiskImage(source: .embedded)

    public enum State: CustomStringConvertible {
        case ready
        case downloading
        case installing
        case installFailed(Error)

        public var description: String {
            switch self {
            case .ready: "Ready"
            case .downloading: "Downloading"
            case .installing: "Installing"
            case .installFailed(let error): "Failed: \(error)"
            }
        }
    }

    public enum Source {
        case embedded
        case catalog(_ id: CatalogLegacyGuestAppVersion.ID)

        var imageBaseName: String {
            switch self {
            case .embedded: "VirtualBuddyGuest"
            case .catalog(let id): id
            }
        }

        var loggerName: String {
            switch self {
            case .embedded: "Embedded"
            case .catalog(let id): id
            }
        }

        var initialState: State {
            switch self {
            case .embedded: .ready
            case .catalog: .downloading
            }
        }
    }

    private let source: Source
    private var imageBaseName: String { source.imageBaseName }

    @Published public private(set) var state: State

    public init(source: Source) {
        self.source = source
        self.logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "\(Self.self)\(source.loggerName)")
        self.state = source.initialState
    }

    public func installIfNeeded() async throws {
        #if DEBUG
        if await simulateInstall() { return }
        #endif

        switch source {
        case .embedded: try await generateAndInstallEmbeddedGuestDiskImage()
        case .catalog(let id): try await installCatalogDiskImage(id)
        }
    }

    private func installCatalogDiskImage(_ id: CatalogLegacyGuestAppVersion.ID) async throws {
        let app = try await SoftwareCatalog.currentMacCatalog.legacyGuestAppVersions
            .first(where: { $0.id == id })
            .require("Guest app image not found: \(id.quoted).")

        let imagePath = FilePath(installedImageURL)

        if imagePath.exists {
            logger.debug("Catalog disk image already installed at \(imagePath)")

            if let digest = try? imagePath.sha384Digest {
                guard digest.hexString.caseInsensitiveCompare(app.sha384) != .orderedSame else {
                    return
                }

                logger.debug("Local disk image digest doesn't match catalog, will redownload")

                do {
                    try imagePath.delete()
                } catch {
                    logger.error("Error removing cached local disk image: \(error, privacy: .public)")
                }
            }
        }

        logger.debug("Downloading image from \(app.url, privacy: .public)")

        let request = URLRequest(url: app.url)
        let (fileURL, response) = try await URLSession.shared.download(for: request)

        let status = (response as! HTTPURLResponse).statusCode
        try (status == 200).require("HTTP \(status).")

        logger.debug("Copying image to \(imagePath)")

        try FilePath(fileURL).copy(imagePath)

        logger.notice("Image installed for \(id, privacy: .public): \(imagePath, privacy: .public)")
    }

    private func generateAndInstallEmbeddedGuestDiskImage() async throws {
        do {
            logger.debug(#function)

            func performInstall(with digest: String) async throws {
                await MainActor.run { state = .installing }

                try await writeGuestImage(with: digest)

                await MainActor.run { state = .ready }
            }

            let digest = try computeGuestDigest()

            if let currentlyInstalledGuestImageDigest {
                logger.debug("Guest app digest: \(digest, privacy: .public) / Library guest app digest: \(currentlyInstalledGuestImageDigest, privacy: .public)")

                guard digest != currentlyInstalledGuestImageDigest else {
                    logger.debug("Guest digests match, skipping guest image generation")

                    await MainActor.run { state = .ready }

                    return
                }

                logger.debug("Guest digests don't match, generating new guest image")

                try await performInstall(with: digest)
            } else {
                logger.debug("No digest for currently installed image, assuming not installed. Guest app digest: \(digest, privacy: .public)")

                try await performInstall(with: digest)
            }
        } catch {
            logger.error("Guest disk image installation failed. \(error, privacy: .public)")

            await MainActor.run { state = .installFailed(error) }

            throw error
        }
    }

    // MARK: File Paths

    private var generatorScriptURL: URL {
        get throws {
            guard let url = Bundle.virtualCore.url(forResource: "CreateGuestImage", withExtension: "sh") else {
                throw Failure("Couldn't get CreateGuestImage.sh URL within VirtualCore bundle")
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure("CreateGuestImage.sj doesn't exist at \(url.path)")
            }

            return url
        }
    }

    private var imageName: String {
        if let suffix = VBBuildType.current.guestAdditionsImageSuffix {
            imageBaseName + suffix
        } else {
            imageBaseName
        }
    }

    static let imagesRootURL: URL = URL.defaultVirtualBuddyLibraryURL.appendingPathComponent("_GuestImage")

    private var imagesRootURL: URL { Self.imagesRootURL }

    private var installedImageDigestURL: URL {
        imagesRootURL
            .appendingPathComponent("." + imageName)
            .appendingPathExtension("digest")
    }

    public var installedImageURL: URL {
        switch source {
        case .embedded:
            imagesRootURL
                .appendingPathComponent(imageName)
                .appendingPathExtension("dmg")
        case .catalog(let id):
            imagesRootURL
                .appendingPathComponent(id)
                .appendingPathExtension("dmg")
        }
    }

    // MARK: Digest

    private var currentlyInstalledGuestImageDigest: String? {
        guard FileManager.default.fileExists(atPath: installedImageDigestURL.path) else {
            return nil
        }
        do {
            return try String(contentsOf: installedImageDigestURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Failed to read installed image digest at \(self.installedImageDigestURL.path): \(error, privacy: .public)")

            return nil
        }
    }

    private func computeGuestDigest() throws -> String {
        guard let enumerator = FileManager.default.enumerator(at: Bundle.embeddedGuestApp.bundleURL, includingPropertiesForKeys: [.contentTypeKey]) else {
            throw Failure("Couldn't instantiate file enumerator for computing guest app bundle digest")
        }

        var hash = SHA256()

        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
                  let contentType = values.contentType
            else { continue }

            guard contentType.conforms(to: .executable),
                  !contentType.conforms(to: .directory)
            else { continue }

            #if DEBUG
            logger.debug("Computing hash for \(url.lastPathComponent)")
            #endif

            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)

                hash.update(data: data)
            } catch {
                logger.warning("Couldn't compute hash for \(url.lastPathComponent): \(error, privacy: .public)")
            }
        }

        let digest = hash.finalize()
        let hashStr = digest.map { String(format: "%02x", $0) }.joined()

        return hashStr
    }

    // MARK: Installation

    private func writeGuestImage(with digest: String) async throws {
        let scriptPath = try generatorScriptURL.path
        let guestPath = Bundle.embeddedGuestApp.bundlePath
        let size = computeImageSizeInMB(guestAppURL: Bundle.embeddedGuestApp.bundleURL)

        var args: [String] = [
            scriptPath,
            guestPath,
            digest,
            "\(size)MB"
        ]

        if let suffix = VBBuildType.current.guestAdditionsImageSuffix {
            args.append(suffix)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        try p.run()
        p.waitUntilExit()

        let outData = try outPipe.fileHandleForReading.readToEnd()
        let errData = try errPipe.fileHandleForReading.readToEnd()

        #if DEBUG
        if let outData, !outData.isEmpty {
            logger.debug("#### Generator script output (stdout): ####")
            logger.debug("\(String(decoding: outData, as: UTF8.self), privacy: .public)")
        }
        if let errData, !errData.isEmpty {
            logger.debug("#### Generator script output (stderr): ####")
            logger.debug("\(String(decoding: errData, as: UTF8.self), privacy: .public)")
        }
        #endif

        guard p.terminationStatus == 0 else {
            if let message = errData.flatMap({ String(decoding: $0, as: UTF8.self) }) {
                throw Failure(message)
            } else {
                throw Failure("Guest additions disk image generator failed with exit code \(p.terminationStatus)")
            }
        }

        logger.notice("Guest additions disk image generated at \(self.installedImageURL.path, privacy: .public)")
    }

}

public extension Bundle {
    /// Bundle of the VirtualBuddyGuest app embedded in the app's main bundle.
    static let embeddedGuestApp: Bundle = {
        #if DEBUG
        /// Allow using SwiftUI previews with VirtualUI target selected without having to embed VirtualBuddyGuest.app inside VirtualUI.
        guard !ProcessInfo.isSwiftUIPreview else { return Bundle.main }
        #endif
        do {
            guard let url = Bundle.main.sharedSupportURL?.appendingPathComponent("VirtualBuddyGuest.app") else {
                throw Failure("Couldn't get VirtualBuddyGuest.app URL within main app bundle")
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure("VirtualBuddyGuest.app doesn't exist at \(url.path)")
            }

            guard let bundle = Bundle(url: url) else {
                throw Failure("Failed to construct bundle for embedded guest app at \(url.path(percentEncoded: false)).")
            }

            return bundle
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    var minimumSystemVersion: SoftwareVersion {
        guard let versionString: String = self.infoPlistValue(for: "LSMinimumSystemVersion") else { return .empty }
        return SoftwareVersion(string: versionString) ?? .empty
    }
}

public extension SoftwareVersion {
    /// Version of the VirtualBuddyGuest app embedded in the app's main bundle.
    static let embeddedGuestApp = Bundle.embeddedGuestApp.softwareVersion
}

// MARK: - Virtualization Extensions

extension VZVirtioBlockDeviceConfiguration {

    static func guestAdditionsDisk(for configuration: VBMacConfiguration) async throws -> VZVirtioBlockDeviceConfiguration? {
        let image: GuestAdditionsDiskImage = if let guestAppVersion = configuration.guestAppVersion {
            GuestAdditionsDiskImage(source: .catalog(guestAppVersion))
        } else {
            GuestAdditionsDiskImage.default
        }

        let guestImageURL = image.installedImageURL

        guard FileManager.default.fileExists(atPath: guestImageURL.path) else { return nil }

        let guestAttachment = try VZDiskImageStorageDeviceAttachment(url: guestImageURL, readOnly: true)

        return VZVirtioBlockDeviceConfiguration(attachment: guestAttachment)
    }

}

// MARK: - Image Size Calculation

private extension GuestAdditionsDiskImage {
    /// Fallback size in case image size can't be calculated.
    static let defaultImageSizeInMB = 32

    /// Just being paranoid in case size computation goes haywire and ends up computing a huge image size.
    static let maxImageSizeInMB = 128

    /// Increase image size slightly when compared to guest app size to account for extra space needed for disk image.
    static let imageSizeMultiplier: Double = 1.1

    func computeImageSizeInMB(guestAppURL: URL) -> Int {
        do {
            guard let enumerator = FileManager.default.enumerator(at: guestAppURL, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .contentTypeKey], options: [], errorHandler: { url, error in
                self.logger.warning("Error enumerating guest app contents at \(url.lastPathComponent, privacy: .public) - \(error, privacy: .public)")
                return true
            }) else {
                throw Failure("Failed to create directory enumerator.")
            }

            var totalSize: Int = 0

            while let file = enumerator.nextObject() as? URL {
                let values = try file.resourceValues(forKeys: [.contentTypeKey, .totalFileAllocatedSizeKey])

                guard let type = values.contentType else {
                    throw Failure("Content type not available for \(file.lastPathComponent)")
                }

                guard !type.conforms(to: .directory) else { continue }

                guard let size = values.totalFileAllocatedSize else {
                    throw Failure("File size not available for \(file.lastPathComponent)")
                }

                totalSize += size
            }

            let totalSizeMB = Int(ceil(Double(totalSize) * Self.imageSizeMultiplier)) / 1000 / 1000

            logger.info("Calculated guest disk image size: \(totalSizeMB, privacy: .public)MB")

            guard totalSizeMB <= Self.maxImageSizeInMB else {
                assertionFailure("\(#function) calculated a size that's larger than the maximum allowed size. Calculated size in MB: \(totalSizeMB), max size in MB: \(Self.maxImageSizeInMB)")
                return Self.maxImageSizeInMB
            }

            return totalSizeMB
        } catch {
            logger.fault("Error computing total guest disk image size. \(error, privacy: .public)")
            return Self.defaultImageSizeInMB
        }
    }

}

extension VBBuildType {
    var guestAdditionsImageSuffix: String? {
        switch self {
        case .debug: "_Debug"
        case .betaDebug: "_Beta_Debug"
        case .release: nil
        case .betaRelease: "_Beta"
        case .devRelease: "_Dev"
        }
    }
}

extension FilePath {
    var sha384Digest: Data {
        get throws { try Data(contentsOf: url, options: .mappedIfSafe).sha384Digest }
    }
}

extension Data {
    var sha384Digest: Data { Data(SHA384.hash(data: self)) }
}

// MARK: - Debug Simulation

#if DEBUG
private extension GuestAdditionsDiskImage {
    func simulateInstall() async -> Bool {
        guard UserDefaults.standard.bool(forKey: "VBSimulateGuestDiskImageGeneration") else {
            return false
        }

        logger.debug("Guest disk image will not be generated because VBSimulateGuestDiskImageGeneration is enabled.")

        await MainActor.run {
            state = .installing
        }

        let delaySeconds = UserDefaults.standard.integer(forKey: "VBDelayGuestDiskImageGenerationBySeconds")
        if delaySeconds > 0 {
            logger.debug("Simulating guest disk image install with custom delay of \(delaySeconds) seconds")

            try? await Task.sleep(for: .seconds(delaySeconds))
        } else {
            logger.debug("Simulating guest disk image install with default delay")

            try? await Task.sleep(for: .seconds(3))
        }

        guard !UserDefaults.standard.bool(forKey: "VBSimulateGuestDiskImageGenerationError") else {
            logger.debug("Simulating guest disk image install error.")
            await MainActor.run {
                state = .installFailed("This is a simulated error for debugging.")
            }
            return true
        }

        logger.debug("Simulated guest disk image install completed")

        await MainActor.run {
            state = .ready
        }

        return true
    }
}
#endif
