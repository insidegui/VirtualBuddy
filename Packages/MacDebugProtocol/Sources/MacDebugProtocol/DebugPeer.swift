import Darwin
import Foundation
import Security

/// The code identity required of the process at the other end of a local socket.
/// The kernel records the peer's audit token when the connection is made, so the
/// check follows that exact process image and cannot be redirected by reusing its PID.
public struct DebugPeerRequirement: @unchecked Sendable {
    private let requirement: SecRequirement

    public init(_ text: String) throws {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else {
            throw MacDebugError("Invalid code requirement for the debugger connection.")
        }
        self.requirement = requirement
    }

    /// The designated requirement of the running program. An app and the helper
    /// executables signed as part of its bundle satisfy the same requirement.
    public static func currentApplication() throws -> Self {
        var current: SecCode?
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &current) == errSecSuccess, let current,
              SecCodeCopyStaticCode(current, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else {
            throw MacDebugError("This app needs a code signature to accept debugger connections.")
        }
        return Self(requirement)
    }

    private init(_ requirement: SecRequirement) { self.requirement = requirement }

    fileprivate func validate(_ token: audit_token_t) throws {
        let attributes = [kSecGuestAttributeAudit: withUnsafeBytes(of: token) { Data($0) }] as CFDictionary
        var peer: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &peer) == errSecSuccess, let peer,
              SecCodeCheckValidity(peer, [], requirement) == errSecSuccess else {
            throw POSIXError(.EACCES)
        }
    }
}

extension DebugSocket {
    /// Rejects a peer that runs as another user or does not satisfy the code requirement.
    public func requirePeer(_ requirement: DebugPeerRequirement) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        var token = audit_token_t()
        var size = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid(),
              getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
              size == MemoryLayout<audit_token_t>.size else { throw POSIXError(.EACCES) }
        try requirement.validate(token)
    }
}
