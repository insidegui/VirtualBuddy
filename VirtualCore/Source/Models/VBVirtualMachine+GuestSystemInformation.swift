import Foundation
import VirtualWormhole

/// Stored separately from editable VM configuration and installation metadata.
public struct VBGuestSystemInformation: Codable, Equatable, Sendable {
    public var version = 1
    /// Host time, so an incorrect clock in the guest does not affect freshness.
    public var receivedAt: Date
    public var information: GuestSystemInformation

    public init(receivedAt: Date, information: GuestSystemInformation) {
        self.receivedAt = receivedAt
        self.information = information
    }
}

public extension VBVirtualMachine {
    static let guestSystemInformationFileName = "GuestSystemInfo.plist"

    mutating func recordGuestSystemInformation(_ information: GuestSystemInformation, receivedAt: Date = .now) throws {
        let record = VBGuestSystemInformation(receivedAt: receivedAt, information: information)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try write(encoder.encode(record), forMetadataFileNamed: Self.guestSystemInformationFileName)
        guestSystemInformation = record
    }

    /// Missing, corrupt, or future-version reports must never prevent opening a VM.
    mutating func reloadGuestSystemInformation() {
        guard let data = metadataContents(Self.guestSystemInformationFileName),
              let record = try? PropertyListDecoder().decode(VBGuestSystemInformation.self, from: data),
              record.version == 1 else {
            guestSystemInformation = nil
            return
        }
        guestSystemInformation = record
    }
}
