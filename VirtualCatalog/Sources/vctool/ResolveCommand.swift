import Foundation
import ArgumentParser
import VirtualCatalog

extension CatalogCommand {

    struct ResolveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resolve",
            abstract: "Resolves a VirtualBuddy software catalog for a given environment."
        )

        @Option(name: [.short, .long], help: "Path to the catalog JSON file.")
        var input: String

        @Option(help: "Custom host version.")
        var host: SoftwareVersion?

        @Option(help: "Custom MobileDevice version.")
        var mobileDevice: SoftwareVersion?

        @Flag(help: "Specify guest platform.")
        var guestPlatform: CatalogGuestPlatform = .mac

        @Option(help: "Show results for a specific build.")
        var build: String?

        func run() async throws {
            let url = try input.resolvedURL.ensureExistingFile()

            let catalog = try SoftwareCatalog(contentsOf: url)

            var env = CatalogResolutionEnvironment.current
            if let host {
                env.hostVersion = host
            }
            if let mobileDevice {
                env.mobileDeviceVersion = mobileDevice
            }
            env.guestPlatform = guestPlatform

            let resolved = try ResolvedCatalog(environment: env, catalog: catalog)

            if let build {
                guard let targetImage = resolved.groups.flatMap(\.restoreImages).first(where: { $0.image.build == build }) else {
                    throw "Build not found: \(build)"
                }
                printResult(for: targetImage)
            } else {
                for group in resolved.groups {
                    print("## \(group.name)")
                    print()

                    for resolvedImage in group.restoreImages {
                        printResult(for: resolvedImage)
                    }
                }
            }
        }

        func printResult(for resolvedImage: ResolvedRestoreImage) {
            let image = resolvedImage.image

            print("### \(image.name) (\(image.build))")
            print("  - Guest: \(resolvedImage.status.cliDescription)")
            print("  - Host: \(resolvedImage.requirements.status.cliDescription)")
            print("  - Features:")
            for feature in resolvedImage.features {
                print("    - \(feature.feature.name)")
                print("      - \(feature.status.cliDescription)")
            }
            print()
        }
    }

}
