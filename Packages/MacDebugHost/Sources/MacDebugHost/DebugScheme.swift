import Foundation
import MacDebugProtocol

/// A project may rely entirely on Xcode's automatically generated app schemes.
public struct DebugScheme {
    public let name: String
    public var projectName: String { owner.deletingPathExtension().lastPathComponent }
    private let owner: URL
    private let container: URL
    private let document: XMLDocument
    private let reference: XMLElement

    private static func element(_ name: String, _ attributes: [String: String] = [:]) -> XMLElement {
        let node = XMLElement(name: name)
        node.setAttributesWith(attributes)
        return node
    }

    public static func choices(in container: URL) throws -> [Self] {
        var projects = [URL]()
        if container.pathExtension == "xcodeproj" { projects = [container] }
        else {
            let workspace = try XMLDocument(contentsOf: container.appendingPathComponent("contents.xcworkspacedata"), options: [.nodeLoadExternalEntitiesNever])
            func walk(_ parent: XMLNode, base: URL) {
                for case let child as XMLElement in parent.children ?? [] {
                    guard let location = child.attribute(forName: "location")?.stringValue,
                          let separator = location.firstIndex(of: ":") else { continue }
                    let kind = location[..<separator]
                    let path = String(location[location.index(after: separator)...])
                    let url: URL
                    switch kind {
                    case "absolute": url = URL(fileURLWithPath: path)
                    case "group": url = base.appendingPathComponent(path)
                    case "container", "self": url = container.deletingLastPathComponent().appendingPathComponent(path)
                    default: continue
                    }
                    if child.name == "Group" { walk(child, base: url) }
                    if child.name == "FileRef", url.pathExtension == "xcodeproj" { projects.append(url.standardizedFileURL) }
                }
            }
            if let root = workspace.rootElement() { walk(root, base: container.deletingLastPathComponent()) }
        }
        let owners = [container] + projects.filter { $0 != container }
        var choices = [Self]()
        for owner in owners {
            for dir in ["xcuserdata/\(NSUserName()).xcuserdatad/xcschemes", "xcshareddata/xcschemes"] {
                for file in (try? FileManager.default.contentsOfDirectory(at: owner.appendingPathComponent(dir), includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "xcscheme" {
                    guard let xml = try? XMLDocument(contentsOf: file, options: [.nodeLoadExternalEntitiesNever]),
                          binding(in: xml) == nil,
                          let ref = try xml.nodes(forXPath: "/Scheme/LaunchAction/BuildableProductRunnable/BuildableReference").first as? XMLElement,
                          ref.attribute(forName: "BuildableName")?.stringValue?.hasSuffix(".app") == true else { continue }
                    choices.append(.init(name: file.deletingPathExtension().lastPathComponent, owner: owner, container: container, document: xml, reference: ref))
                }
            }
        }
        for project in projects {
            for target in try targets(in: project) {
                guard !choices.contains(where: { $0.reference.attribute(forName: "BlueprintIdentifier")?.stringValue == target.id && $0.name == target.name }) else { continue }
                let ref = element("BuildableReference", ["BuildableIdentifier": "primary", "BlueprintIdentifier": target.id, "BuildableName": target.product, "BlueprintName": target.name, "ReferencedContainer": "container:" + project.lastPathComponent])
                let root = element("Scheme", ["version": "1.7"])
                let build = element("BuildAction", ["buildImplicitDependencies": "YES", "parallelizeBuildables": "YES"])
                let entries = element("BuildActionEntries")
                let entry = element("BuildActionEntry", ["buildForRunning": "YES"])
                entry.addChild(ref)
                entries.addChild(entry)
                build.addChild(entries)
                root.addChild(build)
                root.addChild(element("LaunchAction", ["buildConfiguration": target.configuration]))
                choices.append(.init(name: target.name, owner: project, container: container, document: XMLDocument(rootElement: root), reference: ref))
            }
        }
        return choices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func targets(in project: URL) throws -> [(id: String, name: String, product: String, configuration: String)] {
        let modern = project.appendingPathComponent("project.xcproj")
        if FileManager.default.fileExists(atPath: modern.path) {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: modern), options: [.json5Allowed]) as? [String: Any]
            let configs = (object?["configurations"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            return (object?["targets"] as? [[String: Any]] ?? []).compactMap {
                guard $0["product-type"] as? String == "application", let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
                return (id, name, (($0["product"] as? String ?? (name + ".app")) as NSString).lastPathComponent, configs.first(where: { $0 == "Debug" }) ?? configs.first ?? "Debug")
            }
        }
        let data = try Data(contentsOf: project.appendingPathComponent("project.pbxproj"))
        let object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let objects = object?["objects"] as? [String: [String: Any]] ?? [:]
        return objects.compactMap { id, target in
            guard target["productType"] as? String == "com.apple.product-type.application", let name = target["name"] as? String,
                  let product = target["productReference"] as? String, let path = objects[product]?["path"] as? String else { return nil }
            let list = objects[target["buildConfigurationList"] as? String ?? ""]
            let configurations = (list?["buildConfigurations"] as? [String] ?? []).compactMap { objects[$0]?["name"] as? String }
            return (id, name, path, configurations.first(where: { $0 == "Debug" }) ?? configurations.first ?? "Debug")
        }
    }

    public struct Binding {
        public let destination: UUID
        public let scheme: UUID
        let target: String
    }

    // Xcode rewrites the XML when the developer edits Run arguments. Keep the
    // binding in the pre-action as well as the XML attributes Xcode can discard.
    public static func binding(in document: XMLDocument) -> Binding? {
        let actions = (try? document.nodes(forXPath: "/Scheme/LaunchAction/PreActions/ExecutionAction/ActionContent/@scriptText")) ?? []
        for action in actions {
            let header = action.stringValue?.components(separatedBy: "\n").first?.components(separatedBy: " ") ?? []
            if header.count == 5, header[0] == "#", header[1] == "MacDebug", let destination = UUID(uuidString: header[2]), let scheme = UUID(uuidString: header[3]) {
                return Binding(destination: destination, scheme: scheme, target: header[4])
            }
        }
        guard let root = document.rootElement(),
              let destination = root.attribute(forName: "MacDebugDestination")?.stringValue.flatMap(UUID.init(uuidString:)),
              let scheme = root.attribute(forName: "MacDebugBinding")?.stringValue.flatMap(UUID.init(uuidString:)),
              let target = root.attribute(forName: "MacDebugTarget")?.stringValue else { return nil }
        return Binding(destination: destination, scheme: scheme, target: target)
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Call when the developer asks for the scheme. The binding is recorded as their approval
    /// for Run actions from this scheme to start the destination and launch the app on it.
    public func install(destination: UUID, named destinationName: String, configuration: DebugHostConfiguration,
                        bindings: any DebugBindingStore) throws -> URL {
        let fm = FileManager.default
        let directory = container.appendingPathComponent("xcuserdata/\(NSUserName()).xcuserdatad/xcschemes")
        let filename = (name + " — " + destinationName).replacingOccurrences(of: "/", with: "-") + ".xcscheme"
        let output = directory.appendingPathComponent(filename)
        let id: UUID
        let targetID = reference.attribute(forName: "BlueprintIdentifier")?.stringValue ?? ""
        if fm.fileExists(atPath: output.path) {
            let existing = try XMLDocument(contentsOf: output, options: [.nodeLoadExternalEntitiesNever])
            guard let binding = Self.binding(in: existing), binding.destination == destination, binding.target == targetID else {
                throw MacDebugError("Another scheme already uses the name \(filename). Rename it or choose another scheme.")
            }
            id = binding.scheme
        } else { id = UUID() }
        guard let xml = document.copy() as? XMLDocument, let root = xml.rootElement(), let launch = root.elements(forName: "LaunchAction").first else { throw MacDebugError("Missing scheme Run action.") }
        func set(_ node: XMLElement, _ key: String, _ value: String) {
            node.removeAttribute(forName: key)
            node.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
        }
        set(root, "MacDebugDestination", destination.uuidString)
        set(root, "MacDebugBinding", id.uuidString)
        set(root, "MacDebugTarget", targetID)
        for child in launch.children ?? [] where ["BuildableProductRunnable", "PathRunnable", "RemoteRunnable", "MacroExpansion"].contains(child.name) { child.detach() }
        // Xcode uses the scheme's runnable to label the process in its navigator.
        // The custom launch commands below connect LLDB to the remote executable.
        let runnable = Self.element("BuildableProductRunnable", ["runnableDebuggingMode": "0"])
        runnable.addChild(reference.copy() as! XMLNode)
        launch.addChild(runnable)
        let pre = launch.elements(forName: "PreActions").first ?? Self.element("PreActions")
        if pre.parent == nil { launch.insertChild(pre, at: 0) }
        let action = Self.element("ExecutionAction", ["ActionType": "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction"])
        let cli = configuration.helperURL
        guard targetID.range(of: "^[a-zA-Z0-9_.-]+$", options: .regularExpression) != nil else { throw MacDebugError("The selected app has an invalid Xcode target identifier.") }
        let script = "# MacDebug \(destination.uuidString) \(id.uuidString) \(targetID)\nexec " + Self.shellQuote(cli.path) + " prepare " + Self.shellQuote(output.path) + "\n"
        let content = Self.element("ActionContent", ["title": "Prepare app on " + destinationName, "scriptText": script])
        let environment = Self.element("EnvironmentBuildable")
        environment.addChild(reference.copy() as! XMLNode)
        content.addChild(environment)
        action.addChild(content)
        pre.addChild(action)
        if owner != container {
            let base = owner.deletingLastPathComponent()
            for case let node as XMLElement in try xml.nodes(forXPath: "//BuildableReference") {
                guard let ref = node.attribute(forName: "ReferencedContainer")?.stringValue, ref.hasPrefix("container:") else { continue }
                let full = base.appendingPathComponent(String(ref.dropFirst(10))).standardizedFileURL
                let original = container.deletingLastPathComponent().standardizedFileURL.pathComponents
                let dest = full.pathComponents
                let common = zip(original, dest).prefix(while: { $0 == $1 }).count
                set(node, "ReferencedContainer", "container:" + (Array(repeating: "..", count: original.count - common) + Array(dest.dropFirst(common))).joined(separator: "/"))
            }
        }
        set(launch, "launchStyle", "2")
        set(launch, "selectedDebuggerIdentifier", "Xcode.DebuggerFoundation.Debugger.LLDB")
        set(launch, "selectedLauncherIdentifier", "Xcode.DebuggerFoundation.Launcher.LLDB")
        set(launch, "customLaunchCommandPauseAfterCommands", "NO")
        guard let module = Bundle.module.url(forResource: "mac_debug", withExtension: "py")?.path else {
            throw MacDebugError("Could not find the packaged LLDB module.")
        }
        guard !module.contains("`"), !module.contains("\n") else { throw MacDebugError("The LLDB module path contains an unsupported character.") }
        let escaped = module.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let runtime = Data(configuration.runtimeDirectory.path.utf8).base64EncodedString()
        set(launch, "customLaunchCommand", "command script import \"\(escaped)\"\nmac-debug-connect \(id.uuidString) \(runtime)")
        try bindings.register(DebugBinding(id: id, destination: destination, target: targetID))
        try DebugTools.directory(directory)
        // Foundation emits literal newlines in attributes. XML readers normalize
        // those to spaces, collapsing both custom LLDB commands into one.
        let serialized = NSMutableString(string: xml.xmlString(options: [.nodePrettyPrint]))
        let attributes = try NSRegularExpression(pattern: #"\s[\w:.-]+\s*=\s*"([^"]*)""#)
        for match in attributes.matches(in: serialized as String, range: NSRange(location: 0, length: serialized.length)).reversed() {
            let range = match.range(at: 1)
            let value = serialized.substring(with: range)
            let escaped = value.replacingOccurrences(of: "\n", with: "&#10;")
                .replacingOccurrences(of: "\r", with: "&#13;").replacingOccurrences(of: "\t", with: "&#9;")
            if value != escaped { serialized.replaceCharacters(in: range, with: escaped) }
        }
        try Data((serialized as String).utf8).write(to: output, options: .atomic)
        return output
    }
}
