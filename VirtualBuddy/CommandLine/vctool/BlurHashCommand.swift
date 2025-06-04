import Foundation
import ArgumentParser
import VirtualUI
import BuddyFoundation

struct BlurHashCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blurhash",
        abstract: "Generates blur hashes."
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
