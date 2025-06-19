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

public final class GuestAdditionsDiskImage {

    private lazy var logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: String(describing: Self.self))

    public static let current = GuestAdditionsDiskImage()

    public func installIfNeeded() async throws {
        do {
            logger.debug(#function)

            let embeddedDigest = try computeEmbeddedGuestDigest()

            if let currentlyInstalledGuestImageDigest {
                logger.debug("Embedded guest app digest: \(embeddedDigest, privacy: .public) / Library guest app digest: \(currentlyInstalledGuestImageDigest, privacy: .public)")

                guard embeddedDigest != currentlyInstalledGuestImageDigest else {
                    logger.debug("Guest digests match, skipping guest image generation")
                    return
                }

                logger.debug("Guest digests don't match, generating new guest image with embedded guest")

                try await writeGuestImage(with: embeddedDigest)
            } else {
                logger.debug("No digest for currently installed image, assuming not installed. Embedded guest app digest: \(embeddedDigest, privacy: .public)")

                try await writeGuestImage(with: embeddedDigest)
            }
        } catch {
            logger.error("Guest disk image installation failed. \(error, privacy: .public)")
            throw error
        }
    }

    // MARK: File Paths

    private var embeddedGuestAppURL: URL {
        get throws {
            guard let url = Bundle.main.sharedSupportURL?.appendingPathComponent("VirtualBuddyGuest.app") else {
                throw Failure("Couldn't get VirtualBuddyGuest.app URL within main app bundle")
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure("VirtualBuddyGuest.app doesn't exist at \(url.path)")
            }

            return url
        }
    }

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

    private var _imageBaseName: String { "VirtualBuddyGuest" }

    private var imageName: String {
        if let suffix = VBBuildType.current.guestAdditionsImageSuffix {
            _imageBaseName + suffix
        } else {
            _imageBaseName
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
        imagesRootURL
            .appendingPathComponent(imageName)
            .appendingPathExtension("dmg")
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

    private func computeEmbeddedGuestDigest() throws -> String {
        let url = try embeddedGuestAppURL
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentTypeKey]) else {
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
        let guestURL = try embeddedGuestAppURL
        let guestPath = guestURL.path
        let size = computeImageSizeInMB(guestAppURL: guestURL)

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

// MARK: - Virtualization Extensions

extension VZVirtioBlockDeviceConfiguration {

    static var guestAdditionsDisk: VZVirtioBlockDeviceConfiguration? {
        get throws {
            let guestImageURL = GuestAdditionsDiskImage.current.installedImageURL

            guard FileManager.default.fileExists(atPath: guestImageURL.path) else { return nil }

            let guestAttachment = try VZDiskImageStorageDeviceAttachment(url: guestImageURL, readOnly: true)

            return VZVirtioBlockDeviceConfiguration(attachment: guestAttachment)
        }
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
