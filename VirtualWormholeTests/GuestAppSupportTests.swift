import Foundation
import Testing
@testable import VirtualCore

struct GuestAppSupportTests {
    private static let legacyApps = [
        CatalogLegacyGuestAppVersion(id: "monterey", url: URL(fileURLWithPath: "/monterey.dmg"), sha384: "",
            guestAppVersion: "1.4", minGuestVersion: "12.3", maxGuestVersion: "12.99.99"),
        CatalogLegacyGuestAppVersion(id: "ventura", url: URL(fileURLWithPath: "/ventura.dmg"), sha384: "",
            guestAppVersion: "2.1", minGuestVersion: "13", maxGuestVersion: "13.99.99"),
        CatalogLegacyGuestAppVersion(id: "sonoma", url: URL(fileURLWithPath: "/sonoma.dmg"), sha384: "",
            guestAppVersion: "2.2", minGuestVersion: "14", maxGuestVersion: "14.99.99")
    ]

    @Test(arguments: [
        ("12.0", GuestAppSupport.unsupported),
        ("12.6.1", .unsupported),
        ("13.0", .sharedFoldersOnly),
        ("13.7", .sharedFoldersOnly),
        ("14.0", .full),
        ("15.0", .full),
        ("27.0", .full)
    ])
    func knownGuestOS(version: String, expected: GuestAppSupport) {
        #expect(resolve(version: SoftwareVersion(string: version)) == expected)
    }

    @Test func legacyOverridesNeverEnableClipboard() {
        for app in Self.legacyApps {
            #expect(resolve(version: "15", override: app.id) == .sharedFoldersOnly)
            #expect(resolve(version: "12.6.1", override: app.id) == .unsupported)
        }
        #expect(resolve(version: "15", override: "removed-catalog-entry") == .sharedFoldersOnly)
    }

    @Test func importedGuestsUseLegacySelection() {
        #expect(resolve(version: nil, override: "monterey") == .unsupported)
        #expect(resolve(version: .empty, override: "monterey") == .unsupported)
        #expect(resolve(version: nil, override: "ventura") == .sharedFoldersOnly)
        #expect(resolve(version: nil, override: "sonoma") == .sharedFoldersOnly)
        #expect(resolve(version: nil, override: "removed-catalog-entry") == .sharedFoldersOnly)
        #expect(resolve(version: nil) == .full)
    }

    @Test func latestRequirementComesFromEmbeddedApp() {
        #expect(GuestAppSupport.resolve(guestType: .mac, guestVersion: "14", latestMinimumVersion: "15",
            guestAppVersion: nil, legacyApps: Self.legacyApps) == .sharedFoldersOnly)
    }

    @Test func linuxDoesNotUseMacGuestApp() {
        #expect(GuestAppSupport.resolve(guestType: .linux, guestVersion: nil, latestMinimumVersion: "14",
            guestAppVersion: nil, legacyApps: Self.legacyApps) == .unsupported)
    }

    private func resolve(version: SoftwareVersion?, override: String? = nil) -> GuestAppSupport {
        GuestAppSupport.resolve(guestType: .mac, guestVersion: version, latestMinimumVersion: "14",
            guestAppVersion: override, legacyApps: Self.legacyApps)
    }
}
