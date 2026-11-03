import Foundation
import Testing
@testable import VirtualWormhole

struct GuestSystemInformationTests {
    @Test func sipSummaryDoesNotConfuseCustomProtectionsWithOverallStatus() {
        let descriptions: [(String?, GuestSystemInformation.SIPStatus)] = [
            ("System Integrity Protection status: enabled.", .enabled),
            ("System Integrity Protection status: disabled.", .disabled),
            ("System Integrity Protection status: unknown (Custom Configuration).\n\nFilesystem Protections: disabled", .custom),
            ("Unexpected output\nFilesystem Protections: enabled", .unknown),
            (nil, .unknown)
        ]
        for (description, status) in descriptions {
            #expect(GuestSystemInformation(osVersion: "26.0", sipDescription: description).sipStatus == status)
        }
    }

    @Test func oldHostDoesNotAdvertiseSystemInformation() throws {
        let reply = try JSONDecoder().decode(InitializeGuestReply.self, from: Data(#"{"notifications":[]}"#.utf8))
        #expect(reply.capabilities == nil)
        // Existing guests ignore the additive field in new host replies.
        struct LegacyReply: Decodable { let notifications: Set<String> }
        let data = try JSONEncoder().encode(InitializeGuestReply(notifications: ["existing"], capabilities: [SystemInformationGuestService.capability]))
        #expect(try JSONDecoder().decode(LegacyReply.self, from: data).notifications == ["existing"])
    }

    @Test func liveCollectorReturnsCurrentSystemWithoutRequiringPrivileges() async throws {
        let information = try await SystemInformationCollector.collect()
        #expect(!information.osVersion.isEmpty)
        #expect(information.osBuild?.isEmpty == false)
        #expect(information.processorCount == ProcessInfo.processInfo.processorCount)
        #expect(information.memoryBytes == ProcessInfo.processInfo.physicalMemory)
        #expect(information.bootDate != nil)
        #expect(information.sipDescription?.isEmpty == false)
    }
}
