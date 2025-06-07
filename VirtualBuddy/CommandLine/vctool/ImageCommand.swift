import Foundation
import ArgumentParser
import FragmentZip
import BuddyFoundation

extension CatalogCommand {
    struct ImageCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "image",
            abstract: "Manipulates restore images in the VirtualBuddy catalog.",
            subcommands: [
                AddCommand.self
            ]
        )

        // MARK: - Add Command

        struct AddCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "add",
                abstract: "Adds a new macOS release to a VirtualBuddy software catalog based on an IPSW URL."
            )

            @Option(name: [.short, .long], help: "URL to the IPSW file.")
            var ipsw: String

            @Option(name: [.short, .long], help: "ID of the release channel (devbeta or regular).")
            var channel: String

            @Option(name: [.short, .long], help: "User-facing name for the release (ex: \"macOS 15.0 Developer Beta 4\").")
            var name: String

            @Option(name: [.short, .long], help: "Path to the software catalog JSON file that will be updated.")
            var output: String

            @Flag(name: .shortAndLong, help: "Replace existing build if it already exists in the catalog.")
            var force = false

            func run() async throws {
                let ipswURL = try URL(validating: ipsw)
                let catalogURL = try output.resolvedURL.ensureExistingFile()

                fputs("Detecting download size...\n", stderr)

                let contentLength = try await ipswURL.contentLength()

                var catalog = try SoftwareCatalog(contentsOf: catalogURL)

                fputs("Reading build manifest from remote IPSW...\n", stderr)

                let zip = FragmentZip(url: ipswURL)

                let fileURL = try await zip.download(filePath: "BuildManifest.plist")

                let manifest = try BuildManifest(contentsOf: fileURL)

                guard let identity = manifest.buildIdentities.first(where: { $0.hasVMInformation }) else {
                    throw "Couldn't find a build identity with VM information in the specified IPSW. Are you sure this IPSW supports macOS VMs?"
                }

                let majorVersion = SoftwareVersion(majorVersionFrom: manifest.productVersion)

                guard let group = catalog.groups.first(where: { $0.majorVersion == majorVersion }) else {
                    throw "Couldn't find a group with majorVersion = \(majorVersion). If this is a new major version of macOS, a new group must be added to the catalog manually before running this command."
                }

                guard catalog.channels.contains(where: { $0.id == channel }) else {
                    throw "Couldn't find \"\(channel)\" channel in the catalog. Catalog channels: \(catalog.channels.map(\.id).joined(separator: ", "))"
                }

                fputs("Found group \(group.name)\n", stderr)

                let requirementSet: RequirementSet

                if let existingSet = catalog.requirementSets.first(where: { $0.matches(info: identity.info) }) {
                    fputs("Found existing requirement set \(existingSet.id)\n", stderr)

                    requirementSet = existingSet
                } else {
                    fputs("Found no existing requirement set matching properties from manifest, will create a new one: \(identity.info.requirementsDescription)\n", stderr)

                    requirementSet = RequirementSet(
                        id: UUID().uuidString,
                        minCPUCount: identity.info.virtualMachineMinCPUCount ?? 2,
                        minMemorySizeMB: identity.info.virtualMachineMinMemorySizeMB ?? 4096,
                        minVersionHost: identity.info.virtualMachineMinHostOS ?? SoftwareVersion(major: 12, minor: 0, patch: 0)
                    )

                    catalog.requirementSets.insert(requirementSet, at: 0)
                }

                let image = RestoreImage(
                    id: manifest.productBuildVersion,
                    group: group.id,
                    channel: channel,
                    requirements: requirementSet.id,
                    name: name,
                    build: manifest.productBuildVersion,
                    version: manifest.productVersion,
                    mobileDeviceMinVersion: identity.info.mobileDeviceMinVersion,
                    url: ipswURL,
                    downloadSize: UInt64(contentLength)
                )

                let index = catalog.restoreImages.firstIndex(where: { $0.id == image.id })

                if let index {
                    guard force else {
                        fputs("\n❌ Build \(image.id) already exists in the catalog. Use --force flag to update it.\n\n", stderr)
                        Darwin.exit(1)
                    }

                    catalog.restoreImages.remove(at: index)
                }

                catalog.restoreImages.insert(image, at: index ?? 0)

                let successMessage = index == nil ? "Added image to catalog" : "Updated image in catalog"
                fputs("✅ \(successMessage):\n\n", stderr)

                fputs("\(image)\n\n", stderr)

                try catalog.write(to: catalogURL)

                fputs("✅ Done!\n\n", stderr)
            }
        }
    }
}
