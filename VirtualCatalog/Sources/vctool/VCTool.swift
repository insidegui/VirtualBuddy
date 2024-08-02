import Foundation
import ArgumentParser
import VirtualCatalog
import AppKit

@main
struct VCTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vctool",
        abstract: "Tools for updating the VirtualBuddy software catalog.",
        subcommands: [
            CatalogCommand.self,
            IPSWCommand.self,
            MobileDeviceCommand.self
        ],
        defaultSubcommand: CatalogCommand.self
    )
}
