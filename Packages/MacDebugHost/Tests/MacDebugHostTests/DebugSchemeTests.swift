import Foundation
import Testing
import MacDebugProtocol
@testable import MacDebugHost

struct DebugSchemeTests {
    @Test func generatedWorkspaceSchemeBuildsTheAppAndPreservesLaunchCommands() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ws = root.appendingPathComponent("Dev.xcworkspace")
        let project = root.appendingPathComponent("Apps/Example.xcodeproj")
        for folder in [ws, project] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try #"<Workspace><Group location="group:Apps"><FileRef location="group:Example.xcodeproj"/></Group></Workspace>"#.write(to: ws.appendingPathComponent("contents.xcworkspacedata"), atomically: true, encoding: .utf8)
        try #"{targets:[{id:"APP", name:"App", "product-type":"application", product:"Products/Example.app"}]}"#.write(to: project.appendingPathComponent("project.xcproj"), atomically: true, encoding: .utf8)
        let choice = try #require(try DebugScheme.choices(in: ws).first)
        let vm = UUID()
        let app = URL(fileURLWithPath: "/Applications/VirtualBuddy.app")
        let links = root.appendingPathComponent("Stable Links")
        let helper = app.appendingPathComponent("Contents/MacOS/helper")
        let configuration = DebugHostConfiguration(applicationURL: app, helperURL: helper, runtimeDirectory: root, linksDirectory: links)
        let bindings = MemoryBindingStore()
        let file = try choice.install(destination: vm, named: "My VM", configuration: configuration, bindings: bindings)
        let xml = try XMLDocument(contentsOf: file, options: [])
        let launch = try #require(try xml.nodes(forXPath: "//LaunchAction").first as? XMLElement)
        #expect(launch.attribute(forName: "customLaunchCommand")?.stringValue?.components(separatedBy: "\n").count == 2)
        #expect(try launch.nodes(forXPath: "BuildableProductRunnable/BuildableReference/@BlueprintIdentifier").first?.stringValue == "APP")
        #expect(try launch.nodes(forXPath: "PathRunnable").isEmpty)
        #expect(launch.attribute(forName: "launchStyle")?.stringValue == "2")
        #expect(try xml.nodes(forXPath: "//BuildableReference/@ReferencedContainer").allSatisfy { $0.stringValue == "container:Apps/Example.xcodeproj" })
        let id = xml.rootElement()?.attribute(forName: "MacDebugBinding")?.stringValue
        xml.rootElement()?.removeAttribute(forName: "MacDebugDestination")
        xml.rootElement()?.removeAttribute(forName: "MacDebugBinding")
        xml.rootElement()?.removeAttribute(forName: "MacDebugTarget")
        #expect(DebugScheme.binding(in: xml)?.destination == vm)
        #expect(DebugScheme.binding(in: xml)?.scheme.uuidString == id)
        _ = try choice.install(destination: vm, named: "My VM", configuration: configuration, bindings: bindings)
        #expect(try XMLDocument(contentsOf: file, options: []).rootElement()?.attribute(forName: "MacDebugBinding")?.stringValue == id)
        #expect(throws: (any Error).self) { try choice.install(destination: UUID(), named: "My VM", configuration: configuration, bindings: bindings) }
        let bindingID = try #require(id.flatMap(UUID.init(uuidString:)))
        let approved = try #require(bindings.binding(for: bindingID))
        #expect(approved.destination == vm && approved.target == "APP" && approved.scheme == file)

        // The scheme refers to the links only, so the app can move and the scheme can be renamed.
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains(app.path) && !text.contains(file.lastPathComponent) && !text.contains(".bundle"))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: links.appendingPathComponent("helper").path) == helper.path)
        let module = try FileManager.default.destinationOfSymbolicLink(atPath: links.appendingPathComponent("mac_debug.py").path)
        #expect(FileManager.default.fileExists(atPath: module))
        #expect(launch.attribute(forName: "customLaunchCommand")?.stringValue?.hasPrefix("command script import \"\(links.path)/mac_debug.py\"\n") == true)

        let moved = URL(fileURLWithPath: "/Applications/Renamed.app/Contents/MacOS/helper")
        try DebugHostConfiguration(applicationURL: app, helperURL: moved, runtimeDirectory: root, linksDirectory: links).refreshLinks()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: links.appendingPathComponent("helper").path) == moved.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: links.path).sorted() == ["helper", "mac_debug.py"])

        // The pre-action prints the helper it resolved through the link, followed by its arguments.
        let script = try #require(try xml.nodes(forXPath: "//PreActions/ExecutionAction/ActionContent/@scriptText").first?.stringValue)
        let echo = root.appendingPathComponent("echo helper")
        try "#!/bin/sh\necho \"$0\" \"$@\"\n".write(to: echo, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: echo.path)
        try DebugHostConfiguration(applicationURL: app, helperURL: echo, runtimeDirectory: root, linksDirectory: links).refreshLinks()
        func run() throws -> (status: Int32, output: String) {
            let shell = Process(), output = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", script]
            shell.standardOutput = output
            shell.standardError = Pipe()
            try shell.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            return (shell.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        #expect(try run() == (0, "\(echo.path) prepare \(bindingID.uuidString)\n"))
        try FileManager.default.removeItem(at: links)
        #expect(try run().status == 1)

        // Xcode keeps the binding when the developer renames or duplicates the scheme.
        let schemes = file.deletingLastPathComponent()
        let renamed = schemes.appendingPathComponent("Renamed.xcscheme")
        try FileManager.default.moveItem(at: file, to: renamed)
        let copy = try XMLDocument(contentsOf: renamed, options: [])
        let arguments = XMLElement(name: "CommandLineArguments")
        let argument = XMLElement(name: "CommandLineArgument")
        argument.setAttributesWith(["argument": "-copy", "isEnabled": "YES"])
        arguments.addChild(argument)
        (try copy.nodes(forXPath: "//LaunchAction").first as? XMLElement)?.addChild(arguments)
        try copy.xmlData.write(to: schemes.appendingPathComponent("Copy.xcscheme"))
        func options(_ settings: [String: String]) throws -> [String] {
            let found = try DebugScheme.installed(binding: bindingID, settings: settings)
            #expect(found.binding.destination == vm)
            return try DebugScheme.launchOptions(from: found.document, settings: settings).arguments
        }
        #expect(try options(["WORKSPACE_PATH": ws.path, "SCHEME_NAME": "Renamed"]) == [])
        #expect(try options(["WORKSPACE_PATH": ws.path, "SCHEME_NAME": "Copy"]) == ["-copy"])
        #expect(throws: (any Error).self) { try options(["WORKSPACE_PATH": project.appendingPathComponent("project.xcworkspace").path]) }
        #expect(throws: (any Error).self) { try DebugScheme.installed(binding: UUID(), settings: ["WORKSPACE_PATH": ws.path]) }
    }

    @Test func argumentsAndBuildSettingsAreData() throws {
        let xml = try XMLDocument(xmlString: #"""
        <Scheme><LaunchAction><CommandLineArguments>
        <CommandLineArgument argument="-label 'two words' $(NAME) ''" isEnabled="YES"/>
        <CommandLineArgument argument="unused" isEnabled="NO"/>
        </CommandLineArguments><EnvironmentVariables>
        <EnvironmentVariable key="LABEL" value="${NAME}" isEnabled="YES"/>
        </EnvironmentVariables></LaunchAction></Scheme>
        """#, options: [])
        let value = "Guest App; $HOME"
        let options = try DebugScheme.launchOptions(from: xml, settings: ["NAME": value])
        #expect(options.arguments == ["-label", "two words", value, ""])
        #expect(options.environment == ["LABEL": value])
    }
}
