import Foundation
import ArgumentParser
import VirtualCore
import VirtualUI
import BuddyFoundation

struct BlurHashCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blurhash",
        abstract: "Encodes or decodes blur hashes.",
        subcommands: [
            BlurHashEncodeCommand.self,
            BlurHashDecodeCommand.self,
        ]
    )
}

private struct BlurHashEncodeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encode",
        abstract: "Encodes an image into a blur hash."
    )

    @Argument(help: "Path to input image.")
    var input: String

    @Option(name: .shortAndLong, help: "Number of blur hash components.")
    var components: Int = 4

    @Option(name: .shortAndLong, help: "Size of thumbnail used to generate the blur hash.")
    var size: Int = 128

    @Option(name: .shortAndLong, help: "HEIC compression quality of thumbnail used to generate the blur hash.")
    var quality: Double = 0.6

    func run() async throws {
        let inputURL = try URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            .ensureExistingFile()

        let blurHashComponents: (Int, Int) = (Int(CGSize.vbBlurHashSize.width), Int(CGSize.vbBlurHashSize.height))

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).heic")

        try inputURL.vctool_encodeHEIC(to: tempURL, maxSize: size, quality: quality)

        let image = try NSImage(contentsOf: tempURL)
            .require("Error loading input image.")

        let blurHash = try image.blurHash(numberOfComponents: blurHashComponents)
            .require("Error generating blur hash.")

        try? FileManager.default.removeItem(at: tempURL)

        print(blurHash)
    }
}

private struct BlurHashDecodeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decode",
        abstract: "Decodes a blur hash into an image."
    )

    @Argument(help: "Blur hash string.")
    var input: String

    @Option(name: .shortAndLong, help: "Path to output image file.", completion: .file())
    var output: String

    @Option(name: .shortAndLong, help: "Number of blur hash components.")
    var components: Int = 4

    @Option(name: .shortAndLong, help: "The width of the output image.")
    var width: Int = 1024

    @Option(name: .shortAndLong, help: "The height of the output image.")
    var height: Int = 1024

    @Option(name: .shortAndLong, help: "HEIC compression quality of the output image.")
    var quality: Double = 0.6

    @Option(name: .shortAndLong, help: "The punch parameter for the blur hash.")
    var punch: Float = 1.0

    func run() async throws {
        print("input: \(input.quoted)")
        let image = try NSImage(blurHash: input, size: CGSize(width: components, height: components), punch: punch)
            .require("Error decoding blur hash into image.")

        image.size = CGSize(width: width, height: height)

        try image.vb_encodeHEIC(to: output.resolvedURL, options: [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationImageMaxPixelSize: max(width, height)
        ] as CFDictionary)

        print("✅ Blur hash image saved to \(output.quoted)\n")
    }
}
