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
        let configuration = DebugHostConfiguration(applicationURL: app, helperURL: app.appendingPathComponent("Contents/MacOS/helper"), runtimeDirectory: root)
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
        #expect(approved.destination == vm && approved.target == "APP")
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
