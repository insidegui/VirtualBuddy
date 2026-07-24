import Foundation
import ArgumentParser
import AppKit
import BuddyFoundation
import VirtualUI
import CryptoKit

extension CatalogCommand {
    struct LegacyGuestAppCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "legacyguestapp",
            abstract: "Modify legacy guest app disk images.",
            subcommands: [
                AddCommand.self,
            ]
        )

        struct AddCommand: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "add",
                abstract: "Adds a legacy guest app disk image to the catalog.",
                discussion: """
                This command is used to add legacy builds of the VirtualBuddyGuest app to the catalog so that users running legacy guest OSes
                can still have a version of the guest app that supports them.
                
                If run with a disk image matching the file name of a disk image already in the catalog, the corresponding entry in the catalog is updated.
                """
            )

            @Option(name: [.short, .long], help: "Path to an existing catalog JSON file that will be updated with the new group.")
            var output: String

            @Option(help: "Remote base URL where legacy guest app disk images will be served from.")
            var baseURL: String = "https://raw.githubusercontent.com/insidegui/VirtualBuddy/refs/heads/main/data/LegacyGuestApp"

            @Argument(help: "Path to VirtualBuddyGuest app DMG created with dmgdist.", completion: .file(extensions: ["dmg"]))
            var input: String

            func run() async throws {
                let catalogURL = try output.resolvedURL.ensureExistingFile()
                var catalog = try SoftwareCatalog(contentsOf: catalogURL)

                let imageURL = URL(filePath: input)
                let imageData = try Data(contentsOf: imageURL, options: .mappedIfSafe)
                let baseURL = try URL(string: self.baseURL).require("Invalid base URL \(self.baseURL.quoted)")
                let remoteURL = baseURL.appending(path: imageURL.lastPathComponent)

                let mountURL = FileManager.default.temporaryDirectory
                    .appending(path: "VirtualBuddyGuest-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
                var isMounted = false
                defer {
                    if isMounted {
                        let hdiutilDetach = Process()
                        hdiutilDetach.executableURL = URL(filePath: "/usr/bin/hdiutil")
                        hdiutilDetach.arguments = [
                            "detach",
                            mountURL.path(percentEncoded: false),
                            "-quiet",
                        ]

                        if (try? hdiutilDetach.run()) != nil {
                            hdiutilDetach.waitUntilExit()
                        }
                    }

                    try? FileManager.default.removeItem(at: mountURL)
                }

                let hdiutilAttach = Process()
                hdiutilAttach.executableURL = URL(filePath: "/usr/bin/hdiutil")
                hdiutilAttach.arguments = [
                    "attach",
                    input,
                    "-readonly",
                    "-nobrowse",
                    "-mountpoint",
                    mountURL.path(percentEncoded: false),
                ]
                try hdiutilAttach.run()
                hdiutilAttach.waitUntilExit()

                try (hdiutilAttach.terminationStatus == 0).require("Error mounting disk image.")
                isMounted = true

                let bundleURL = mountURL.appending(path: "VirtualBuddyGuest.app")

                try bundleURL.requireExistingDirectory()

                let bundle = try Bundle(url: bundleURL).require("Error constructing bundle at \(bundleURL.path(percentEncoded: false).quoted).")

                let infoDict = try bundle.infoDictionary.require("Bundle has no info dictionary!")

                let appVersionString = try cast(infoDict["CFBundleShortVersionString"], as: String.self, "CFBundleShortVersionString not a string.")
                let minOSVersionString = try cast(infoDict["LSMinimumSystemVersion"], as: String.self, "LSMinimumSystemVersion not a string.")

                let appVersion = try SoftwareVersion(string: appVersionString).require("Invalid app version string \(appVersionString.quoted).")
                let minOSVersion = try SoftwareVersion(string: minOSVersionString).require("Invalid min OS version string \(minOSVersionString.quoted).")
                let maxOSVersion = SoftwareVersion(major: minOSVersion.major, minor: 99, patch: 99)

                let sha384 = SHA384.hash(data: imageData)
                    .map { String(format: "%02x", $0) }
                    .joined()

                let entry = CatalogLegacyGuestAppVersion(
                    id: imageURL.deletingPathExtension().lastPathComponent,
                    url: remoteURL,
                    sha384: sha384,
                    guestAppVersion: appVersion,
                    minGuestVersion: minOSVersion,
                    maxGuestVersion: maxOSVersion
                )

                let isUpdate: Bool
                if let index = catalog.legacyGuestAppVersions.firstIndex(where: { $0.id == entry.id }) {
                    catalog.legacyGuestAppVersions[index] = entry
                    isUpdate = true
                } else {
                    catalog.legacyGuestAppVersions.append(entry)
                    isUpdate = false
                }

                try catalog.write(to: catalogURL)

                if isUpdate {
                    print("✅ Updated \(entry.id)")
                } else {
                    print("✅ Added \(entry.id)")
                }
            }
        }
    }
}
