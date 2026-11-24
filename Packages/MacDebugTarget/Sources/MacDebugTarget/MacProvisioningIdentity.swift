import Foundation
import MacDebugProtocol

/// System Information reports the provisioning identifier for physical and virtual Macs.
/// Its spelling is significant to Apple's provisioning service.
public actor MacProvisioningIdentity {
    public static let current = MacProvisioningIdentity()
    private var cached: String?

    public func udid() async throws -> String {
        if let cached { return cached }
        let pipe = Pipe()
        async let profiler: Void = DebugTools.run(URL(fileURLWithPath: "/usr/sbin/system_profiler"),
                                                  ["SPHardwareDataType", "-json", "-timeout", "10"], standardOutput: pipe)
        var data = Data()
        for try await byte in pipe.fileHandleForReading.bytes {
            guard data.count < 1 << 20 else { throw MacDebugError("System Information returned too much hardware data.") }
            data.append(byte)
        }
        try await profiler
        struct Hardware: Decodable { let provisioning_UDID: String? }
        struct Report: Decodable { let SPHardwareDataType: [Hardware] }
        guard let value = try JSONDecoder().decode(Report.self, from: data).SPHardwareDataType.first?.provisioning_UDID,
              !value.isEmpty else { throw MacDebugError("System Information could not read this Mac’s provisioning UDID.") }
        cached = value
        return value
    }
}
