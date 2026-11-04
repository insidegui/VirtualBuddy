import Foundation
import Testing
import Virtualization
@testable import VirtualCore

struct LiveDisplayConfigurationTests {
    @Test func macDisplayRequestIncludesResolutionAndDensity() throws {
        let original = VBDisplayDevice()
        var requested = original
        requested.width = 2560
        requested.height = 1440
        requested.pixelsPerInch = 180
        let updated = try requested.validatedLiveDisplay(replacing: original, guestType: .mac)
        let configuration = try #require(updated.runtimeDisplayConfiguration(for: .mac) as? VZMacGraphicsDisplayConfiguration)
        #expect(configuration.widthInPixels == 2560)
        #expect(configuration.heightInPixels == 1440)
        #expect(configuration.pixelsPerInch == 180)
    }

    @Test func linuxDisplayRequestUsesScanoutAndPreservesDensity() throws {
        let original = VBDisplayDevice()
        var requested = original
        requested.width = 1280
        requested.height = 720
        requested.pixelsPerInch = 200
        let updated = try requested.validatedLiveDisplay(replacing: original, guestType: .linux)
        #expect(updated.pixelsPerInch == original.pixelsPerInch)
        let configuration = try #require(updated.runtimeDisplayConfiguration(for: .linux) as? VZVirtioGraphicsScanoutConfiguration)
        #expect(configuration.widthInPixels == 1280)
        #expect(configuration.heightInPixels == 720)
    }

    @Test func invalidGeometryAndChangedIdentityAreRejected() {
        let original = VBDisplayDevice()
        var requests = [VBDisplayDevice]()
        var request = original
        request.width = 0
        requests.append(request)
        request = original
        request.height = VBDisplayDevice.displayHeightRange.upperBound + 1
        requests.append(request)
        request = original
        request.pixelsPerInch = 0
        requests.append(request)
        request = original
        request.id = UUID()
        requests.append(request)
        for request in requests {
            #expect(throws: (any Error).self) {
                try request.validatedLiveDisplay(replacing: original, guestType: .mac)
            }
        }
    }

    @Test func restoringPreferencesPreservesConstructionConfiguration() throws {
        var configuration = VBMacConfiguration()
        let original = VBDisplayDevice()
        configuration.hardware.displayDevices = [original]
        var edited = original
        edited.width = 2560
        edited.height = 1440
        edited.automaticallyReconfiguresDisplay = true
        #expect(try configuration.restoringLiveDisplays([edited]) == [edited])
        #expect(configuration.hardware.displayDevices == [original])
        #expect(throws: SavedSessionError.self) { try configuration.restoringLiveDisplays([]) }
        #expect(throws: SavedSessionError.self) { try configuration.restoringLiveDisplays([VBDisplayDevice()]) }
    }
}
