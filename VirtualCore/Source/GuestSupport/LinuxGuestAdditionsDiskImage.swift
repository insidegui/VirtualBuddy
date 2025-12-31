//
//  LinuxGuestAdditionsDiskImage.swift
//  VirtualCore
//
//  Created by VirtualBuddy on 2024.
//

import Foundation
import Virtualization
import CryptoKit
import OSLog
import Combine

/// Manages the Linux guest tools ISO disk image that gets attached to Linux VMs.
/// Similar to `GuestAdditionsDiskImage` but creates an ISO instead of DMG.
public final class LinuxGuestAdditionsDiskImage: ObservableObject {

    private lazy var logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: String(describing: Self.self))

    public static let current = LinuxGuestAdditionsDiskImage()

    public enum State: CustomStringConvertible {
        case ready
        case installing
        case installFailed(Error)

        public var description: String {
            switch self {
            case .ready: "Ready"
            case .installing: "Installing"
            case .installFailed(let error): "Failed: \(error)"
            }
        }
    }

    @MainActor
    @Published public private(set) var state = State.ready

    public func installIfNeeded() async throws {
        do {
            logger.debug(#function)

            func performInstall(with digest: String) async throws {
                await MainActor.run { state = .installing }

                try await writeGuestImage(with: digest)

                await MainActor.run { state = .ready }
            }

            let embeddedDigest = try computeEmbeddedToolsDigest()

            if let currentlyInstalledDigest {
                logger.debug("Embedded Linux tools digest: \(embeddedDigest, privacy: .public) / Library digest: \(currentlyInstalledDigest, privacy: .public)")

                guard embeddedDigest != currentlyInstalledDigest else {
                    logger.debug("Linux tools digests match, skipping ISO generation")

                    await MainActor.run { state = .ready }

                    return
                }

                logger.debug("Linux tools digests don't match, generating new ISO")

                try await performInstall(with: embeddedDigest)
            } else {
                logger.debug("No digest for currently installed Linux tools, assuming not installed. Embedded digest: \(embeddedDigest, privacy: .public)")

                try await performInstall(with: embeddedDigest)
            }
        } catch {
            logger.error("Linux guest tools ISO generation failed. \(error, privacy: .public)")

            await MainActor.run { state = .installFailed(error) }

            throw error
        }
    }

    // MARK: File Paths

    private var embeddedToolsURL: URL {
        get throws {
            guard let url = Bundle.virtualCore.url(forResource: "LinuxGuestAdditions", withExtension: nil) else {
                throw Failure("Couldn't get LinuxGuestAdditions URL within VirtualCore bundle")
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure("LinuxGuestAdditions doesn't exist at \(url.path)")
            }

            return url
        }
    }

    private var generatorScriptURL: URL {
        get throws {
            guard let url = Bundle.virtualCore.url(forResource: "CreateLinuxGuestImage", withExtension: "sh") else {
                throw Failure("Couldn't get CreateLinuxGuestImage.sh URL within VirtualCore bundle")
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw Failure("CreateLinuxGuestImage.sh doesn't exist at \(url.path)")
            }

            return url
        }
    }

    private var _imageBaseName: String { "VirtualBuddyLinuxTools" }

    private var imageName: String {
        if let suffix = VBBuildType.current.guestAdditionsImageSuffix {
            _imageBaseName + suffix
        } else {
            _imageBaseName
        }
    }

    private var imagesRootURL: URL { GuestAdditionsDiskImage.imagesRootURL }

    private var installedImageDigestURL: URL {
        imagesRootURL
            .appendingPathComponent(imageName)
            .appendingPathExtension("digest")
    }

    public var installedImageURL: URL {
        imagesRootURL
            .appendingPathComponent(imageName)
            .appendingPathExtension("iso")
    }

    // MARK: Digest

    private var currentlyInstalledDigest: String? {
        guard FileManager.default.fileExists(atPath: installedImageDigestURL.path) else {
            return nil
        }
        do {
            return try String(contentsOf: installedImageDigestURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Failed to read installed Linux tools digest at \(self.installedImageDigestURL.path): \(error, privacy: .public)")

            return nil
        }
    }

    private func computeEmbeddedToolsDigest() throws -> String {
        let url = try embeddedToolsURL
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey]) else {
            throw Failure("Couldn't instantiate file enumerator for computing Linux tools digest")
        }

        var hash = SHA256()

        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }

            // Skip design documents and other non-essential files
            let filename = fileURL.lastPathComponent
            guard !filename.hasSuffix(".md") || filename == "README.md" else { continue }
            guard !filename.hasPrefix(".") else { continue }

            #if DEBUG
            logger.debug("Computing hash for \(fileURL.lastPathComponent)")
            #endif

            do {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                hash.update(data: data)
            } catch {
                logger.warning("Couldn't compute hash for \(fileURL.lastPathComponent): \(error, privacy: .public)")
            }
        }

        let digest = hash.finalize()
        let hashStr = digest.map { String(format: "%02x", $0) }.joined()

        return hashStr
    }

    // MARK: Installation

    private func writeGuestImage(with digest: String) async throws {
        let scriptPath = try generatorScriptURL.path
        let toolsPath = try embeddedToolsURL.path
        let destPath = installedImageURL.path

        // Ensure destination directory exists
        try FileManager.default.createDirectory(at: imagesRootURL, withIntermediateDirectories: true)

        let args: [String] = [
            scriptPath,
            toolsPath,
            destPath,
            digest
        ]

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
            logger.debug("#### Linux ISO generator script output (stdout): ####")
            logger.debug("\(String(decoding: outData, as: UTF8.self), privacy: .public)")
        }
        if let errData, !errData.isEmpty {
            logger.debug("#### Linux ISO generator script output (stderr): ####")
            logger.debug("\(String(decoding: errData, as: UTF8.self), privacy: .public)")
        }
        #endif

        guard p.terminationStatus == 0 else {
            if let message = errData.flatMap({ String(decoding: $0, as: UTF8.self) }) {
                throw Failure(message)
            } else {
                throw Failure("Linux guest tools ISO generator failed with exit code \(p.terminationStatus)")
            }
        }

        logger.notice("Linux guest tools ISO generated at \(self.installedImageURL.path, privacy: .public)")
    }

}

// MARK: - Virtualization Extensions

extension VZVirtioBlockDeviceConfiguration {

    static var linuxGuestToolsDisk: VZVirtioBlockDeviceConfiguration? {
        get throws {
            let isoURL = LinuxGuestAdditionsDiskImage.current.installedImageURL

            guard FileManager.default.fileExists(atPath: isoURL.path) else { return nil }

            let attachment = try VZDiskImageStorageDeviceAttachment(url: isoURL, readOnly: true)

            return VZVirtioBlockDeviceConfiguration(attachment: attachment)
        }
    }

}
