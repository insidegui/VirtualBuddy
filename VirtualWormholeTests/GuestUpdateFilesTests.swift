import Foundation
import Testing
@testable import VirtualWormhole

struct GuestUpdateFilesTests {
    @Test func signedImageRoundTripAndExportReplacement() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: directory) }
        let app = directory.appendingPathComponent("VirtualBuddyGuest.app")
        let executable = app.appendingPathComponent("Contents/MacOS/TestGuest")
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "codes.rambo.VirtualBuddyGuest.UpdateTest",
            "CFBundleExecutable": "TestGuest", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try await GuestUpdateCommand().run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        let bundle = try #require(Bundle(url: app))
        let identity = try GuestAppIdentity(bundle: bundle)
        let (image, package) = try await GuestUpdateFiles.createImage(appURL: app)
        defer { try? manager.removeItem(at: image.deletingLastPathComponent()) }
        #expect(package.identity == identity)
        try await GuestUpdateFiles.verify(image, package: package)

        let export = directory.appendingPathComponent("An Export With Spaces.dmg")
        try Data("previous export".utf8).write(to: export)
        try await GuestUpdateFiles.exportExistingImage(image, to: export)
        try await GuestUpdateFiles.verify(export, package: package)

        let mount = directory.appendingPathComponent("Mount")
        try manager.createDirectory(at: mount, withIntermediateDirectories: false)
        try await GuestUpdateCommand().run("/usr/bin/hdiutil", ["attach", export.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path])
        do {
            let candidate = mount.appendingPathComponent("VirtualBuddyGuest.app")
            try GuestUpdateFiles.validateApplication(at: candidate, replacing: app, expected: identity)
            let wrongIdentity = GuestAppIdentity(version: "1.0", build: 1, codeHash: Data([0]), minimumOS: "14.0")
            #expect(throws: GuestAppUpdateError.self) {
                try GuestUpdateFiles.validateApplication(at: candidate, replacing: app, expected: wrongIdentity)
            }
        } catch {
            try? await GuestUpdateCommand().run("/usr/bin/hdiutil", ["detach", mount.path])
            throw error
        }
        try await GuestUpdateCommand().run("/usr/bin/hdiutil", ["detach", mount.path])
        // A modified signed bundle must fail full resource validation.
        try Data("tampered".utf8).write(to: executable)
        #expect(throws: (any Error).self) {
            try GuestUpdateFiles.validateApplication(at: app, replacing: app, expected: identity)
        }
    }

    @Test func applicationExchangeKeepsBothVersionsAndCanRollBack() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: directory) }
        let installed = directory.appendingPathComponent("Installed.app")
        let staged = directory.appendingPathComponent("Replacement.app")
        for (url, value) in [(installed, "old"), (staged, "new")] {
            try manager.createDirectory(at: url, withIntermediateDirectories: false)
            try Data(value.utf8).write(to: url.appendingPathComponent("version"))
        }
        try GuestUpdateFiles.exchangeApplications(installed, staged)
        #expect(try String(contentsOf: installed.appendingPathComponent("version"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: staged.appendingPathComponent("version"), encoding: .utf8) == "old")
        try GuestUpdateFiles.exchangeApplications(installed, staged)
        #expect(try String(contentsOf: installed.appendingPathComponent("version"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: staged.appendingPathComponent("version"), encoding: .utf8) == "new")
    }
}
