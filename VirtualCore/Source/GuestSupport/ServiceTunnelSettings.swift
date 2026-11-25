import Foundation
import VirtualWormhole

extension VBVirtualMachine {
    static func tunnelSetting(approvals: SettingApprovals = .keychain) -> ApprovedVMSetting<[ServiceTunnel]> {
        ApprovedVMSetting("ServiceTunnels", schema: 1, approvals: approvals) { rules in
            guard rules.count <= 32, rules.indices.allSatisfy({ rules[$0].canAdd(to: Array(rules.prefix($0))) }) else {
                throw Failure("Tunnel listeners must be valid and unique on each side.")
            }
        }
    }

    /// Every setting that needs approval has to be listed here for a duplicate made in the library to keep its approval.
    static func carryApprovedSettings(from original: VBVirtualMachine, to copy: VBVirtualMachine) throws {
        try tunnelSetting().carryApproval(from: original, to: copy)
    }

    public var serviceTunnelSettings: ApprovedSettingState<[ServiceTunnel]> { Self.tunnelSetting().read(from: self) }

    public func approveServiceTunnels(_ rules: [ServiceTunnel]) throws {
        try Self.tunnelSetting().approve(rules, in: self)
    }
}
