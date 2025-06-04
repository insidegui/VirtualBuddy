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

        /// Remove any arguments injected by Xcode (such as `-NSDocumentRevisionsDebugMode`).
        /// Also remove first argument, which is the name of the command itself.
        let sanitizedArguments: [String] = CommandLine.arguments
            .suffix(from: 1)
            .filter { !$0.hasPrefix("-NS") && $0 != "YES" && $0 != "NO" }

        if let asyncCommand = command as? AsyncParsableCommand.Type {
            await asyncCommand.main(sanitizedArguments)
        } else {
            command.main(sanitizedArguments)
        }

        /**
         For non-async commands, we have to exit explicitly if the command didn't do it for us,
         otherwise this function will return and the app could end up running from the command-line.

         Placed at the end here just in case the behavior changes for async commands in the future.
         **/
        exit(0)
    }
}
