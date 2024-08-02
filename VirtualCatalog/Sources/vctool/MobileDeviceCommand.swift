import Foundation
import ArgumentParser
import VirtualCatalog

struct MobileDeviceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mobiledevice",
        abstract: "Interacts with the MobileDevice framework on the host.",
        subcommands: [
            VersionCommand.self
        ],
        defaultSubcommand: VersionCommand.self
    )

    struct VersionCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "version",
            abstract: "Retrieves the version of the MobileDevice framework that's currently installed."
        )

        func run() async throws {
            guard let framework = MobileDeviceFramework.current else {
                throw "Couldn't find MobileDevice.framework"
            }

            print(framework.version)
        }
    }
}
