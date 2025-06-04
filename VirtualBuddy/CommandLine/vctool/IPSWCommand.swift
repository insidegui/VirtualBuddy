import Foundation
import ArgumentParser
import FragmentZip

struct IPSWCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ipsw",
        abstract: "Tools for exploring IPSW packages.",
        subcommands: [
            InspectCommand.self,
            ManifestCommand.self
        ],
        defaultSubcommand: InspectCommand.self
    )

    struct ManifestOptions: ParsableArguments {
        @Flag(help: "List only the build identities containing virtual machine information.")
        var vm = false
    }

    // MARK: - Inspect Command

    struct InspectCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "inspect",
            abstract: "Inspects an IPSW file, retrieving information that's relevant to VirtualBuddy."
        )

        @Argument(help: "URL to the IPSW file.")
        var ipsw: String

        @OptionGroup
        var options: ManifestOptions

        func run() async throws {
            let url = try URL(validating: ipsw)

            let zip = FragmentZip(url: url)

            let fileURL = try await zip.download(filePath: "BuildManifest.plist")

            let manifestCommand = ManifestCommand(manifestPath: fileURL.path, options: options)

            try await manifestCommand.run()
        }
    }

    // MARK: - Manifest Command

    struct ManifestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "manifest",
            abstract: "Parses properties from a local BuildManifest.plist file."
        )

        @Argument(help: "Path to a BuildManifest.plist file.")
        var manifestPath: String

        @OptionGroup
        var options: ManifestOptions

        init() { }

        // This initializer is needed because this command is run by InspectCommand.
        init(manifestPath: String, options: ManifestOptions) {
            self.manifestPath = manifestPath
            self.options = options
        }

        func run() async throws {
            let url = try manifestPath.resolvedURL.ensureExistingFile()

            var manifest = try BuildManifest(contentsOf: url)

            manifest.filterBuildIdentities { identity in
                options.vm ? identity.hasVMInformation : true
            }

            print(manifest)
        }
    }

}
