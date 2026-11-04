import Foundation
import Testing
@testable import VirtualCore

struct CatalogAppVersionRequirementTests {
    private var requirements: RequirementSet {
        RequirementSet(id: "test", minCPUCount: 2, minMemorySizeMB: 4096,
                       minVersionHost: "15", minVersionApp: "3.2.1")
    }

    private func environment(appVersion: SoftwareVersion = "3.2.0", hostVersion: SoftwareVersion = "15") -> CatalogResolutionEnvironment {
        CatalogResolutionEnvironment(hostVersion: hostVersion, guestVersion: "15", guestPlatform: .mac,
                                     appVersion: appVersion, mobileDeviceVersion: "999")
    }

    @Test func legacyCatalogDecodesWithoutAppRequirement() throws {
        let data = Data(#"{"id":"legacy","minCPUCount":2,"minMemorySizeMB":4096,"minVersionHost":"13.0.0"}"#.utf8)
        let decoded = try JSONDecoder().decode(RequirementSet.self, from: data)
        #expect(decoded.minVersionApp == nil)
        let resolved = ResolvedRequirementSet(requirements: decoded, status: .supported).updated(with: environment(appVersion: "1"))
        #expect(resolved.status.isSupported)
        #expect(resolved.requiredAppUpdate == nil)
    }

    @Test func appRequirementRoundTrips() throws {
        let data = try JSONEncoder().encode(requirements)
        #expect(try JSONDecoder().decode(RequirementSet.self, from: data) == requirements)
    }

    @Test(arguments: ["3.2.0", "3.2.1", "3.2.2", "3.10.0", "4.0.0"])
    func versionBoundary(version: String) throws {
        let appVersion = try #require(SoftwareVersion(string: version))
        let resolved = ResolvedRequirementSet(requirements: requirements, status: .supported).updated(with: environment(appVersion: appVersion))
        #expect(resolved.status.isSupported == (version != "3.2.0"))
        #expect((resolved.requiredAppUpdate != nil) == (version == "3.2.0"))
    }

    @Test func hostAndAppRequirementsAreBothReported() {
        let resolved = ResolvedRequirementSet(requirements: requirements, status: .supported).updated(with: environment(hostVersion: "14"))
        #expect(resolved.requiredAppUpdate == "3.2.1")
        #expect(resolved.status.message?.contains("VirtualBuddy 3.2.1") == true)
        #expect(resolved.status.message?.contains("macOS 15") == true)
    }

    @Test func resolvingAgainClearsAppRequirementButKeepsHostRequirement() {
        var resolved = ResolvedRequirementSet(requirements: requirements, status: .supported)
        resolved.update(with: environment())
        resolved.update(with: environment(appVersion: "4", hostVersion: "14"))
        #expect(resolved.requiredAppUpdate == nil)
        #expect(resolved.status.isUnsupported)
        resolved.update(with: environment(appVersion: "4"))
        #expect(resolved.status.isSupported)
    }

    @Test func appUpdateRemainsVisibleAlongsideDeviceSupportAndCanBeResolvedAgain() {
        let image = RestoreImage(id: "test", group: "test", channel: "test", requirements: "test", name: "Test OS", build: "test",
                                 version: "15", mobileDeviceMinVersion: "1000", url: URL(fileURLWithPath: "/test.ipsw"), downloadSize: nil)
        var resolved = ResolvedRestoreImage(image: image, channel: .init(id: "test", name: "Test", note: "", icon: "desktopcomputer"), features: [],
                                            requirements: .init(requirements: requirements, status: .supported), status: .supported,
                                            localFileURL: nil, deviceSupportVersion: nil, legacyGuestAppVersion: nil)
        resolved.update(with: environment())
        #expect(resolved.status.title == "VirtualBuddy Update Required")
        #expect(resolved.status.message?.contains("device support") == true)
        var updatedEnvironment = environment(appVersion: "4")
        updatedEnvironment.mobileDeviceVersion = "1000"
        resolved.update(with: updatedEnvironment)
        #expect(resolved.status.isSupported)
        #expect(resolved.requirements.requiredAppUpdate == nil)
    }
}
