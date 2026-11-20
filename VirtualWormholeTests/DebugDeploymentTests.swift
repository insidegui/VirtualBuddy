import Foundation
import Testing
@testable import VirtualWormhole

struct DebugDeploymentTests {
    @Test func signedBundlesReplaceTheSameInstallationAndInvalidUpdatesLeaveItIntact() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let product = root.appendingPathComponent("Build/Example.app")
        let contents = product.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/Example")
        let resources = contents.appendingPathComponent("Resources")
        try DebugTools.directory(executable.deletingLastPathComponent())
        try DebugTools.directory(resources)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let plist = ["CFBundleIdentifier": "test.virtualbuddy.deployment", "CFBundleExecutable": "Example", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let entitlement = root.appendingPathComponent("debug.plist")
        try PropertyListSerialization.data(fromPropertyList: ["com.apple.security.get-task-allow": true], format: .xml, options: 0).write(to: entitlement)
        let payload = resources.appendingPathComponent("revision")
        let link = resources.appendingPathComponent("link")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "revision")
        func deploy(_ revision: String, debuggable: Bool) async throws -> URL {
            try Data(revision.utf8).write(to: payload)
            var sign = ["--force", "--sign", "-", "--timestamp=none"]
            if debuggable { sign += ["--entitlements", entitlement.path] }
            try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/codesign"), sign + [product.path])
            let staging = root.appendingPathComponent(UUID().uuidString)
            try DebugTools.directory(staging)
            let zip = staging.appendingPathComponent("App.zip")
            try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--keepParent", product.path, zip.path])
            return try await DebugTools.install(zip, into: staging).0
        }
        let first = try await deploy("one", debuggable: true)
        let second = try await deploy("two", debuggable: true)
        #expect(first == second)
        let installed = first.appendingPathComponent("Contents/Resources/link")
        #expect(try fm.destinationOfSymbolicLink(atPath: installed.path) == "revision")
        #expect(try Data(contentsOf: installed) == Data("two".utf8))
        await #expect(throws: VBDebugError.self) { try await deploy("three", debuggable: false) }
        #expect(try Data(contentsOf: installed) == Data("two".utf8))
    }
}
