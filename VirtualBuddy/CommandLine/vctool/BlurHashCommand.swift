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

    func run() async throws {
        let inputURL = try URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            .ensureExistingFile()

        let blurHashComponents: (Int, Int) = (Int(CGSize.vbBlurHashSize.width), Int(CGSize.vbBlurHashSize.height))

        let image = try NSImage(contentsOf: inputURL)
            .require("Error loading input image.")

        let blurHash = try image.blurHash(numberOfComponents: blurHashComponents)
            .require("Error generating blur hash.")

        print(blurHash)
    }
}
