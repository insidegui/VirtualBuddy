import Foundation
import ArgumentParser
import VirtualCatalog
import FragmentZip

extension CatalogCommand {
    struct MigrateCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "migrate",
            abstract: "Migrates a version 1 restore image catalog to version 2.",
            discussion: "This command will fetch metadata for each IPSW in the legacy catalog, so it requires an internet connection and may take a while to run."
        )

        @Option(name: [.short, .long], help: "Path to version 1 catalog.")
        var inputPath: String

        @Option(name: [.short, .long], help: "Path where to save the migrated version 2 catalog. If a catalog already exists at this path, all restore images will be removed from it and replaced by the migrated ones from the version 1 catalog, but groups and channels will be retained.")
        var outputPath: String

        func run() async throws {
            /// Any channels not listed here will be excluded from the output catalog.
            let channelIdentifiers: Set<String> = ["devbeta", "regular"]

            let inputURL = try inputPath.resolvedURL.ensureExistingFile()
            let outputURL = outputPath.resolvedURL

            let legacyCatalog = try LegacyCatalog(contentsOf: inputURL)

            var catalog: SoftwareCatalog

            /// If there's an existing version 2 catalog at the output path, then use that catalog as a template, migrating only the restore images from the v1 catalog.
            if outputURL.exists {
                fputs("Using existing version 2 catalog for migration\n", stderr)

                catalog = try SoftwareCatalog(contentsOf: outputURL)

                catalog.restoreImages.removeAll()
            } else {
                fputs("Creating empty version 2 catalog for migration\n", stderr)

                catalog = SoftwareCatalog(apiVersion: 2, minAppVersion: .init(string: "2.0.0")!, channels: [], groups: [], restoreImages: [], features: [], requirementSets: [])
            }

            for legacyChannel in legacyCatalog.channels {
                guard channelIdentifiers.contains(legacyChannel.id), !catalog.channels.contains(where: { $0.id == legacyChannel.id }) else { continue }

                let channel = CatalogChannel(id: legacyChannel.id, name: legacyChannel.name, note: legacyChannel.note, icon: legacyChannel.icon)

                catalog.channels.append(channel)
            }

            if catalog.groups.isEmpty {
                for legacyGroup in legacyCatalog.groups {
                    let group = CatalogGroup(id: legacyGroup.id, name: legacyGroup.name, majorVersion: legacyGroup.majorVersion, image: .placeholder, darkImage: .placeholder)

                    catalog.groups.append(group)
                }
            }

            let requirement_min_host_13 = catalog.requirementSets.first(where: { $0.id == "min_host_13" }) ?? RequirementSet(
                id: "min_host_13",
                minCPUCount: 2,
                minMemorySizeMB: 4096,
                minVersionHost: SoftwareVersion(string: "13.0")!
            )
            let requirement_min_host_12 = catalog.requirementSets.first(where: { $0.id == "min_host_12" }) ?? RequirementSet(
                id: "min_host_12",
                minCPUCount: 2,
                minMemorySizeMB: 4096,
                minVersionHost: SoftwareVersion(string: "12.0")!
            )

            if !catalog.requirementSets.contains(where: { $0.id == requirement_min_host_13.id }) {
                catalog.requirementSets.append(requirement_min_host_13)
            }
            if !catalog.requirementSets.contains(where: { $0.id == requirement_min_host_12.id }) {
                catalog.requirementSets.append(requirement_min_host_12)
            }

            for legacyImage in legacyCatalog.images {
                do {
                    let manifest = try await BuildManifest(remoteIPSWURL: legacyImage.url, build: legacyImage.build)

                    /// Version 13.3 started requiring macOS 13 host, all versions higher than that require macOS 13 host, all versions below that support macOS 12 host.
                    let requirements: RequirementSet = manifest.productVersion >= SoftwareVersion(string: "13.3")! ? requirement_min_host_13 : requirement_min_host_12

                    guard let vmIdentity = manifest.buildIdentities.first(where: { $0.hasVMInformation }) else {
                        throw "Couldn't find a build identity with VM properties"
                    }

                    let image = RestoreImage(
                        id: legacyImage.id,
                        group: legacyImage.group.id,
                        channel: legacyImage.channel.id,
                        requirements: requirements.id,
                        name: legacyImage.name,
                        build: legacyImage.build,
                        version: manifest.productVersion,
                        mobileDeviceMinVersion: vmIdentity.info.mobileDeviceMinVersion,
                        url: legacyImage.url
                    )

                    catalog.restoreImages.append(image)

                    try catalog.write(to: outputURL)
                } catch {
                    fputs("Error processing restore image \(legacyImage.id): \(error)\n", stderr)
                }
            }

            print("Migrated catalog written to \(outputURL.path)")
            print("")
        }
    }
}
