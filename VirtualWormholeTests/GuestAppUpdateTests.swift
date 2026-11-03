import Foundation
import Testing
import CryptoKit
@testable import VirtualWormhole

struct GuestAppUpdateTests {
    private func identity(build: Int = 431, hash: UInt8 = 1, minimumOS: String = "14.0") -> GuestAppIdentity {
        .init(version: "2.3", build: build, codeHash: Data([hash]), minimumOS: minimumOS)
    }

    @Test func staleMountedImagesCannotUndoExplicitUpdates() {
        #expect(!GuestAppIdentity.shouldAutomaticallyInstallMountedBuild(430, over: 431))
        #expect(!GuestAppIdentity.shouldAutomaticallyInstallMountedBuild(431, over: 431))
        #expect(GuestAppIdentity.shouldAutomaticallyInstallMountedBuild(432, over: 431))
        #expect(identity(hash: 2).isUpdate(over: identity(hash: 1)))
        #expect(!identity(build: 430, hash: 2).isUpdate(over: identity()))
        #expect(!identity().isUpdate(over: identity()))
    }

    @Test func updateCompatibilityUsesNumericOSComponentsAndFailsClosed() {
        #expect(identity(minimumOS: "14.2").supports(osVersion: "14.10"))
        #expect(!identity(minimumOS: "14.2").supports(osVersion: "14.1.9"))
        #expect(identity(minimumOS: "14").supports(osVersion: "14.0.0"))
        for invalid in ["", "garbage", "14..0", "14.-1", "14.0.0.0"] {
            #expect(!identity().supports(osVersion: invalid))
            #expect(!identity(minimumOS: invalid).supports(osVersion: "26"))
        }
    }

    @Test @MainActor func badgeRequiresKnownCompatibleOlderAppAndNeverDowngrades() {
        let state = GuestAppUpdateState()
        state.target = identity()
        #expect(!state.updateAvailable)
        state.reportedBuild = 430
        state.osVersion = "13.6"
        #expect(!state.updateAvailable)
        state.osVersion = "14.0"
        #expect(state.updateAvailable)
        #expect(!state.canUpdate)
        state.isConnected = true
        state.supportsRemoteUpdate = true
        #expect(state.canUpdate)
        state.phase = .preparing
        #expect(!state.canUpdate)
        state.phase = .idle
        state.reportedBuild = 432
        #expect(!state.updateAvailable)
        state.reportedBuild = 431
        #expect(!state.updateAvailable)
        state.installed = identity(hash: 2)
        #expect(state.updateAvailable)
    }

    @Test func existingHandshakeDecodesWithoutUpdateSupport() throws {
        let old = Data(#"{"session":"12345678-1234-1234-1234-123456789ABC"}"#.utf8)
        let decoded = try JSONDecoder().decode(InitializeGuest.self, from: old)
        #expect(decoded.appUpdate == nil)
        #expect(decoded.capabilities == nil)
        struct OldHandshake: Decodable { let session: UUID }
        let current = InitializeGuest(session: decoded.session, capabilities: [AppUpdateGuestService.capability],
                                      appUpdate: .init(identity: identity(), osVersion: "26"))
        let data = try JSONEncoder().encode(current)
        #expect(try JSONDecoder().decode(OldHandshake.self, from: data).session == decoded.session)
    }

    @Test func packageDigestRejectsModifiedBytesAndWrongSize() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("valid installer".utf8)
        try bytes.write(to: url)
        let package = GuestAppUpdatePackage(identity: identity(), byteCount: Int64(bytes.count), sha256: Data(SHA256.hash(data: bytes)))
        try await GuestUpdateFiles.verify(url, package: package)
        try Data("changed content".utf8).write(to: url)
        await #expect(throws: GuestAppUpdateError.self) { try await GuestUpdateFiles.verify(url, package: package) }
        try Data().write(to: url)
        await #expect(throws: GuestAppUpdateError.self) { try await GuestUpdateFiles.verify(url, package: package) }
    }
}
