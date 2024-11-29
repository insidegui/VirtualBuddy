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

public extension URL {
    static var embeddedGuestAppURL: URL {
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
}

public final class GuestAdditionsDiskImage {

    private lazy var logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: String(describing: Self.self))

    public static let current = GuestAdditionsDiskImage()

    public func installIfNeeded() async throws {
        logger.debug(#function)

        #if DEBUG
        guard !UserDefaults.isGuestSimulationEnabled else {
            logger.notice("Skipping install: guest simulation enabled")
            return
        }
        #endif

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
    }

    // MARK: File Paths

    private var embeddedGuestAppURL: URL {
        get throws { try URL.embeddedGuestAppURL }
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

    private var imageName: String { "VirtualBuddyGuest" }

    private var imagesRootURL: URL { URL.defaultVirtualBuddyLibraryURL.appendingPathComponent("_GuestImage") }

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
        let guestPath = try embeddedGuestAppURL.path

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [
            scriptPath,
            guestPath,
            digest
        ]
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
            if let message = errData.map({ String(decoding: $0, as: UTF8.self) })?.components(separatedBy: .newlines).last {
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
