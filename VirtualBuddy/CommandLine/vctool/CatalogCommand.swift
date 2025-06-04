import Foundation
import ArgumentParser
import FragmentZip

struct CatalogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "catalog",
        abstract: "Manipulates the VirtualBuddy software catalog",
        subcommands: [
            ImageCommand.self,
            GroupCommand.self,
            MigrateCommand.self
        ]
    )
}
