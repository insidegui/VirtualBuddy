import CryptoKit
import Foundation
import VirtualWormhole

extension VBVirtualMachine {
    static func tunnelSetting(key: @escaping (HostSettingsSigningKey.Access) throws -> P256.Signing.PrivateKey? = HostSettingsSigningKey().key) -> SignedVMSetting<[ServiceTunnel]> {
        SignedVMSetting("ServiceTunnels", schema: 1, key: key) { rules in
            guard rules.count <= 32, rules.indices.allSatisfy({ rules[$0].canAdd(to: Array(rules.prefix($0))) }) else {
                throw Failure("Tunnel listeners must be valid and unique on each side.")
            }
        }
    }

    public var serviceTunnelSettings: SignedSettingState<[ServiceTunnel]> { Self.tunnelSetting().read(from: self) }

    public func approveServiceTunnels(_ rules: [ServiceTunnel]) throws {
        try Self.tunnelSetting().approve(rules, in: self)
    }
}
