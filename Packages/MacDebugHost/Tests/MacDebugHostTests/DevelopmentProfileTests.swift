import Foundation
import MacDebugProtocol
import Testing
@testable import MacDebugHost

struct DevelopmentProfileTests {
    @Test func scalarWildcardGrantsStringListEntitlements() {
        #expect(DevelopmentProfile.covers("*", ["applinks:example.com", "webcredentials:example.com"]))
        #expect(DevelopmentProfile.covers("*", ["CloudKit"]))
        #expect(!DevelopmentProfile.covers("*", ["CloudKit", true] as [Any]))
        #expect(!DevelopmentProfile.covers("*", ["mode": "CloudKit"]))
        #expect(!DevelopmentProfile.covers("CloudKit", ["CloudKit", "CloudDocuments"]))
        #expect(!DevelopmentProfile.covers(["CloudKit"], ["CloudKit", "CloudDocuments"]))
    }

    @Test func grantsCoverAllRequestedValues() {
        #expect(DevelopmentProfile.covers(["TEAM.*", "group.example"], ["TEAM.app", "group.example"]))
        #expect(!DevelopmentProfile.covers(["TEAM.*"], ["TEAM.app", "group.example"]))
        #expect(!DevelopmentProfile.covers("TEAM.app", "TEAM.application"))
        #expect(DevelopmentProfile.covers(["mode": ["read", "write"]], ["mode": ["read"]]))
        #expect(!DevelopmentProfile.covers(true, 1))
    }

    @Test func onlyAnAlteredEmbeddedProfileCanBeResealed() async throws {
        try await DebugTools.withTemporaryDirectory { root in
            let app = root.appendingPathComponent("Sample.app")
            let contents = app.appendingPathComponent("Contents")
            let macOS = contents.appendingPathComponent("MacOS")
            let resources = contents.appendingPathComponent("Resources")
            try DebugTools.directory(macOS)
            try DebugTools.directory(resources)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("Sample"))
            let info = ["CFBundleIdentifier": "test.provisioning.seal", "CFBundleExecutable": "Sample", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            let profile = contents.appendingPathComponent("embedded.provisionprofile")
            let resource = resources.appendingPathComponent("example")
            try Data([1]).write(to: profile)
            try Data([2]).write(to: resource)
            try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["-f", "-s", "-", app.path])
            #expect(try !DebugCodeSignature(app).needsProfileReseal(at: profile))
            try Data([3]).write(to: profile)
            #expect(try DebugCodeSignature(app).needsProfileReseal(at: profile))
            try Data([4]).write(to: resource)
            #expect(throws: MacDebugError.self) { try DebugCodeSignature(app).needsProfileReseal(at: profile) }
        }
    }
}
