import Foundation
import ArgumentParser

/**
 Declares supported `ParsableCommand`s that VirtualBuddy provides.

 Commands are implemented in the main app binary, but the app's entry point checks the process name
 in order to determine whether a command-line tool should be run instead of the app itself.
 */
struct VirtualBuddyCLI {
    static let supportedEntryPoints: [ParsableCommand.Type] = [
        VCTool.self,
    ]

    static func runCommand(named name: String) async {
        guard let command = supportedEntryPoints.first(where: { $0.configuration.commandName == name }) else {
            return
        }

        if let asyncCommand = command as? AsyncParsableCommand.Type {
            await asyncCommand.main()
        } else {
            command.main()
        }

        /**
         For non-async commands, we have to exit explicitly if the command didn't do it for us,
         otherwise this function will return and the app could end up running from the command-line.

         Placed at the end here just in case the behavior changes for async commands in the future.
         **/
        exit(0)
    }
}
