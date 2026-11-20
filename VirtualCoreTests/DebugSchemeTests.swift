import Foundation
import Testing
import VirtualWormhole
@testable import VirtualCore

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
        let file = try choice.install(vm: vm, named: "My VM", app: app)
        let xml = try XMLDocument(contentsOf: file, options: [])
        let launch = try #require(try xml.nodes(forXPath: "//LaunchAction").first as? XMLElement)
        #expect(launch.attribute(forName: "customLaunchCommand")?.stringValue?.components(separatedBy: "\n").count == 2)
        #expect(try launch.nodes(forXPath: "BuildableProductRunnable").isEmpty)
        #expect(try launch.nodes(forXPath: "PathRunnable/@FilePath").first?.stringValue == "/usr/bin/false")
        #expect(try xml.nodes(forXPath: "//BuildableReference/@ReferencedContainer").allSatisfy { $0.stringValue == "container:Apps/Example.xcodeproj" })
        let id = xml.rootElement()?.attribute(forName: "VirtualBuddyBinding")?.stringValue
        xml.rootElement()?.removeAttribute(forName: "VirtualBuddyVM")
        xml.rootElement()?.removeAttribute(forName: "VirtualBuddyBinding")
        xml.rootElement()?.removeAttribute(forName: "VirtualBuddyTarget")
        #expect(DebugScheme.binding(in: xml)?.vm == vm)
        #expect(DebugScheme.binding(in: xml)?.scheme.uuidString == id)
        _ = try choice.install(vm: vm, named: "My VM", app: app)
        #expect(try XMLDocument(contentsOf: file, options: []).rootElement()?.attribute(forName: "VirtualBuddyBinding")?.stringValue == id)
        #expect(throws: (any Error).self) { try choice.install(vm: UUID(), named: "My VM", app: app) }
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
