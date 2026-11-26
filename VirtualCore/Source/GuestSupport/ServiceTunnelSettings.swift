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

    /// The saved tunnels and whether they can run, under the review the host currently asks for.
    public var serviceTunnelSettings: ApprovedSettingState<[ServiceTunnel]> {
        serviceTunnelSettings(setting: Self.tunnelSetting(), security: .current)
    }

    public func approveServiceTunnels(_ rules: [ServiceTunnel]) throws {
        try approveServiceTunnels(rules, setting: Self.tunnelSetting(), security: .current)
    }

    /// The tunnels a running virtual machine may use right now.
    func runnableServiceTunnels() throws -> [ServiceTunnel] {
        try runnableServiceTunnels(setting: Self.tunnelSetting(), security: .current)
    }

    /// Adds a tunnel requested by the guest without a review, if the host's review level allows that. Returns whether it was added.
    func acceptProposedServiceTunnel(_ tunnel: ServiceTunnel) -> Bool {
        acceptProposedServiceTunnel(tunnel, setting: Self.tunnelSetting(), security: .current)
    }

    func serviceTunnelSettings(setting: ApprovedVMSetting<[ServiceTunnel]>, security: ServiceTunnelSecurity) -> ApprovedSettingState<[ServiceTunnel]> {
        switch security.level() {
        case .reviewAll:
            return setting.read(from: self)
        case .reviewNew:
            let state = setting.read(from: self)
            // Decided on every read and never recorded, so forgetting the reviewed tunnels or asking for
            // more review sends these tunnels back to review.
            if case .needsApproval(let tunnels) = state, security.remembersAll(tunnels) { return .approved(tunnels) }
            return state
        case .reviewNone:
            do { return try setting.unverifiedValue(in: self).map { .approved($0) } ?? .missing }
            catch { return .unavailable(error.localizedDescription) }
        }
    }

    func runnableServiceTunnels(setting: ApprovedVMSetting<[ServiceTunnel]>, security: ServiceTunnelSecurity) throws -> [ServiceTunnel] {
        switch security.level() {
        case .reviewAll:
            return try setting.approvedValue(in: self) ?? []
        case .reviewNew:
            if let approved = try setting.approvedValue(in: self) { return approved }
            guard let tunnels = try setting.unverifiedValue(in: self), security.remembersAll(tunnels) else { return [] }
            return tunnels
        case .reviewNone:
            return try setting.unverifiedValue(in: self) ?? []
        }
    }

    func approveServiceTunnels(_ rules: [ServiceTunnel], setting: ApprovedVMSetting<[ServiceTunnel]>, security: ServiceTunnelSecurity) throws {
        // Without review nothing counts as reviewed: no approval is recorded and nothing is remembered,
        // so whatever is saved meanwhile is reviewed once the host asks for review again.
        guard security.level() != .reviewNone else { return try setting.store(rules, in: self) }
        try setting.approve(rules, in: self)
        do { try security.remember(rules.map(ServiceTunnelIdentity.init)) }
        catch {
            SecuritySettingsLog.logger.error("Unable to remember reviewed service tunnels: \(error.localizedDescription, privacy: .public)")
        }
    }

    func acceptProposedServiceTunnel(_ tunnel: ServiceTunnel, setting: ApprovedVMSetting<[ServiceTunnel]>, security: ServiceTunnelSecurity) -> Bool {
        do {
            let current: [ServiceTunnel]
            switch security.level() {
            case .reviewAll:
                return false
            case .reviewNew:
                guard security.isRemembered(ServiceTunnelIdentity(tunnel)) else { return false }
                if let approved = try setting.approvedValue(in: self) {
                    // The new record isn't approved as a whole, since nobody reviewed it. It runs for as long
                    // as each of its tunnels is remembered, which the ones approved so far have to be as well.
                    try security.remember(approved.map(ServiceTunnelIdentity.init))
                    current = approved
                } else {
                    // Tunnels that are waiting for review stay that way, and nothing gets added behind them.
                    let saved = try setting.unverifiedValue(in: self) ?? []
                    guard security.remembersAll(saved) else { return false }
                    current = saved
                }
            case .reviewNone:
                current = try setting.unverifiedValue(in: self) ?? []
            }
            try setting.store(current + [tunnel], in: self)
            return true
        } catch {
            SecuritySettingsLog.logger.error("A requested service tunnel is left for review: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

extension ServiceTunnelSecurity {
    func remembersAll(_ tunnels: [ServiceTunnel]) -> Bool {
        tunnels.allSatisfy { isRemembered(ServiceTunnelIdentity($0)) }
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
