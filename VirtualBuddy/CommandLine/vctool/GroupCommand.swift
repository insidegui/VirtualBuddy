import Foundation
import ArgumentParser
import AppKit
import BuddyFoundation
import VirtualUI

extension CatalogCommand {
    struct GroupCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "group",
            abstract: "View or modify groups.",
            subcommands: [
                AddCommand.self
            ]
        )

        struct AddCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "add",
                abstract: "Adds a new group to the catalog."
            )

            @Option(help: "Unique identifier for the group (ex: \"sequoia\").")
            var id: String

            @Option(help: "The major version for releases in the group (ex: 15).")
            var version: SoftwareVersion

            @Option(help: "User-friendly name for the group (ex: \"macOS Sequoia\").")
            var name: String

            @Option(help: "Path to an image representing the group (usually that release's default wallpaper).")
            var image: String

            @Option(name: [.short, .long], help: "Path to an existing catalog JSON file that will be updated with the new group.")
            var output: String

            @Option(help: "Remote base URL where catalog will be served from.")
            var baseURL: String = "https://api.virtualbuddy.app/v2"

            func run() async throws {
                let catalogURL = try output.resolvedURL.ensureExistingFile()
                var catalog = try SoftwareCatalog(contentsOf: catalogURL)

                guard let remoteBaseURL = URL(string: baseURL) else {
                    throw "Invalid base URL: \"\(baseURL)\""
                }

                guard !catalog.groups.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
                    throw "A group already exists with id \"\(id)\""
                }

                let imageURL = try image.resolvedURL.ensureExistingFile()

                /// Dark image is expected to be named the same as the image but with the "-dark" suffix.
                let darkImageURL = try imageURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(imageURL.deletingPathExtension().lastPathComponent + "-dark")
                    .appendingPathExtension(imageURL.pathExtension)
                    .ensureExistingFile()

                let localImagesBaseURL = try catalogURL
                    .deletingLastPathComponent()
                    .appending(path: "images", directoryHint: .isDirectory)
                    .ensureExistingDirectory(createIfNeeded: true)

                let localImageURL = localImagesBaseURL
                    .appendingPathComponent(id, conformingTo: .heic)
                let localThumbnailURL = localImagesBaseURL
                    .appendingPathComponent(id + "-thumbnail", conformingTo: .heic)
                let localDarkImageURL = localImagesBaseURL
                    .appendingPathComponent(id + "-dark", conformingTo: .heic)
                let localDarkThumbnailURL = localImagesBaseURL
                    .appendingPathComponent(id + "-dark-thumbnail", conformingTo: .heic)

                let remoteImageURL = remoteBaseURL.appendingPathComponent("images/" + localImageURL.lastPathComponent)
                let remoteThumbnailImageURL = remoteBaseURL.appendingPathComponent("images/" + localThumbnailURL.lastPathComponent)
                let remoteDarkImageURL = remoteBaseURL.appendingPathComponent("images/" + localDarkImageURL.lastPathComponent)
                let remoteDarkThumbnailImageURL = remoteBaseURL.appendingPathComponent("images/" + localDarkThumbnailURL.lastPathComponent)

                try imageURL.vctool_encodeHEIC(to: localImageURL, maxSize: 2048, quality: 0.9)
                try imageURL.vctool_encodeHEIC(to: localThumbnailURL, maxSize: 720, quality: 0.8)
                try darkImageURL.vctool_encodeHEIC(to: localDarkImageURL, maxSize: 2048, quality: 0.9)
                try darkImageURL.vctool_encodeHEIC(to: localDarkThumbnailURL, maxSize: 720, quality: 0.8)

                let blurHashComponents: (Int, Int) = (Int(CGSize.vbBlurHashSize.width), Int(CGSize.vbBlurHashSize.height))

                guard let thumbnailImage = NSImage(contentsOf: localThumbnailURL) else {
                    throw "Failed to load generated thumbnail image from \(localThumbnailURL.path)"
                }
                guard let blurHash = thumbnailImage.blurHash(numberOfComponents: blurHashComponents) else {
                    throw "Failed to generate blur hash from generated thumbnail image at \(localThumbnailURL.path)"
                }

                guard let darkThumbnailImage = NSImage(contentsOf: localDarkThumbnailURL) else {
                    throw "Failed to load generated thumbnail dark image from \(localDarkThumbnailURL.path)"
                }
                guard let darkBlurHash = darkThumbnailImage.blurHash(numberOfComponents: blurHashComponents) else {
                    throw "Failed to generate blur hash from generated dark thumbnail image at \(localDarkThumbnailURL.path)"
                }

                let image = CatalogGraphic(
                    id: id,
                    url: remoteImageURL,
                    thumbnail: CatalogGraphic.Thumbnail(
                        url: remoteThumbnailImageURL,
                        width: Int(thumbnailImage.size.width),
                        height: Int(thumbnailImage.size.height),
                        blurHash: blurHash
                    )
                )

                let darkImage = CatalogGraphic(
                    id: id,
                    url: remoteDarkImageURL,
                    thumbnail: CatalogGraphic.Thumbnail(
                        url: remoteDarkThumbnailImageURL,
                        width: Int(darkThumbnailImage.size.width),
                        height: Int(darkThumbnailImage.size.height),
                        blurHash: darkBlurHash
                    )
                )

                let group = CatalogGroup(
                    id: id,
                    name: name,
                    majorVersion: version,
                    image: image,
                    darkImage: darkImage
                )

                catalog.groups.insert(group, at: 0)

                try catalog.write(to: catalogURL)
            }
        }
    }
}

// MARK: - Helpers

extension URL {
    func vctool_encodeHEIC(to outputURL: URL, maxSize: Int, quality: Double) throws {
        guard let image = NSImage(contentsOf: self) else {
            throw "Image couldn't be loaded from \(self.path)"
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw "Couldn't get CGImage from input image"
        }

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.heic" as CFString, 1, nil) else {
            throw "Failed to create image destination"
        }

        let imageOptions = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationImageMaxPixelSize: maxSize
        ] as CFDictionary

        CGImageDestinationAddImage(destination, cgImage, imageOptions)
        CGImageDestinationFinalize(destination)
    }
}
