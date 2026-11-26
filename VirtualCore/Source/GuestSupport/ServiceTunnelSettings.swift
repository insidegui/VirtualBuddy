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

/// The service tunnels approved for a virtual machine in the library, offered for adding to another virtual machine.
public struct ServiceTunnelSource: Identifiable, Hashable, Sendable {
    public let id: VBVirtualMachine.ID
    public let name: String
    public let tunnels: [ServiceTunnel]

    public init(id: VBVirtualMachine.ID, name: String, tunnels: [ServiceTunnel]) {
        self.id = id
        self.name = name
        self.tunnels = tunnels
    }
}

public extension VMLibraryController {
    /// The other virtual machines in the library that have service tunnels, sorted by name.
    /// Tunnels that are waiting for review are left out, since adding them
    /// to another virtual machine would approve them without the review.
    func serviceTunnelSources(excluding virtualMachine: VBVirtualMachine) -> [ServiceTunnelSource] {
        virtualMachines
            .filter { $0.id != virtualMachine.id }
            .compactMap { candidate in
                guard let tunnels = candidate.serviceTunnelSettings.approvedValue, !tunnels.isEmpty else { return nil }
                return ServiceTunnelSource(id: candidate.id, name: candidate.name, tunnels: tunnels)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
