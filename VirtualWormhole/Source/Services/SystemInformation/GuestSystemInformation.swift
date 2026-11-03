import Foundation

/// A snapshot reported by the guest, independent of the host's VM configuration.
public struct GuestSystemInformation: Codable, Equatable, Sendable {
    public var osVersion: String
    public var osBuild: String?
    public var kernelVersion: String?
    public var computerName: String?
    public var architecture: String?
    public var processorCount: Int?
    public var memoryBytes: UInt64?
    public var bootDate: Date?
    public var guestAppVersion: String?
    public var guestAppBuild: String?
    /// The unmodified output of `csrutil status`, including custom configurations.
    public var sipDescription: String?

    public init(osVersion: String, osBuild: String? = nil, kernelVersion: String? = nil,
                computerName: String? = nil, architecture: String? = nil,
                processorCount: Int? = nil, memoryBytes: UInt64? = nil, bootDate: Date? = nil,
                guestAppVersion: String? = nil, guestAppBuild: String? = nil, sipDescription: String? = nil) {
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.kernelVersion = kernelVersion
        self.computerName = computerName
        self.architecture = architecture
        self.processorCount = processorCount
        self.memoryBytes = memoryBytes
        self.bootDate = bootDate
        self.guestAppVersion = guestAppVersion
        self.guestAppBuild = guestAppBuild
        self.sipDescription = sipDescription
    }

    public enum SIPStatus: Sendable { case enabled, disabled, custom, unknown }

    public var sipStatus: SIPStatus {
        guard let sipDescription else { return .unknown }
        // Match the complete summary, never an individual protection in the details.
        let summary = sipDescription.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
        switch summary {
        case "System Integrity Protection status: enabled.": return .enabled
        case "System Integrity Protection status: disabled.": return .disabled
        case "System Integrity Protection status: unknown (Custom Configuration).": return .custom
        default: return .unknown
        }
    }
}
