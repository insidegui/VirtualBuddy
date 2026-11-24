import CryptoKit
import Foundation
import MacDebugProtocol
import Security

/// A host-side selection aid. macOS performs the authoritative check on the destination,
/// including validation of the DER-encoded profile and the app's signed entitlements.
struct DevelopmentProfile {
    let data: Data
    let expiration: Date
    let grants: [String: Any]
    private let properties: [String: Any]
    private let decoder: CMSDecoder

    init(_ url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: (4 << 20) + 1), !data.isEmpty, data.count <= 4 << 20 else {
            throw MacDebugError("Could not read \(url.lastPathComponent) as a provisioning profile.")
        }
        var decoder: CMSDecoder?
        var content: CFData?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder,
              data.withUnsafeBytes({ CMSDecoderUpdateMessage(decoder, $0.baseAddress!, $0.count) }) == errSecSuccess,
              CMSDecoderFinalizeMessage(decoder) == errSecSuccess,
              CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content,
              let properties = try PropertyListSerialization.propertyList(from: content as Data, format: nil) as? [String: Any],
              let expiration = properties["ExpirationDate"] as? Date, let grants = properties["Entitlements"] as? [String: Any] else {
            throw MacDebugError("Invalid provisioning profile in \(url.lastPathComponent).")
        }
        self.properties = properties
        self.expiration = expiration
        self.grants = grants
        self.data = data
        self.decoder = decoder
    }

    func isCurrent(for udid: String) -> Bool {
        expiration > Date() && ((properties["ProvisionedDevices"] as? [String])?.contains(udid) == true ||
                                properties["ProvisionsAllDevices"] as? Bool == true)
    }

    func matchesSigningIdentity(_ signing: DebugCodeSignature) -> Bool {
        guard let cert = signing.certificate, let team = signing.team,
              (properties["TeamIdentifier"] as? [String])?.contains(team) == true,
              (properties["DeveloperCertificates"] as? [Data])?.contains(cert) == true,
              (properties["Platform"] as? [String])?.contains("OSX") == true,
              let appID = grants["com.apple.application-identifier"] as? String,
              let prefixes = properties["ApplicationIdentifierPrefix"] as? [String],
              prefixes.contains(where: { Self.covers(appID, $0 + "." + signing.identifier) }) else { return false }
        return hasAppleProfileSignature()
    }

    func authorizes(_ signing: DebugCodeSignature, original: DevelopmentProfile, udid: String) -> Bool {
        guard isCurrent(for: udid), matchesSigningIdentity(signing) else { return false }
        // Use the app's signed claims. Some macOS entitlements (including get-task-allow)
        // need no grant, whereas each restricted claim must be covered by the new profile.
        for (key, claim) in signing.entitlements where original.grants[key] != nil || grants[key] != nil ||
            key.hasPrefix("com.apple.developer.") || key == "keychain-access-groups" || key == "com.apple.application-identifier" {
            guard let grant = grants[key], Self.covers(grant, claim) else { return false }
        }
        return true
    }

    private static let appleRoots: [SecCertificate] = {
        var roots: CFArray?
        guard SecTrustCopyAnchorCertificates(&roots) == errSecSuccess else { return [] }
        return (roots as? [SecCertificate] ?? []).filter { root in
            var name: CFString?
            guard SecCertificateCopyCommonName(root, &name) == errSecSuccess, let name = name as String? else { return false }
            return name == "Apple Root CA" || name.hasPrefix("Apple Root CA - ")
        }
    }()

    private func hasAppleProfileSignature() -> Bool {
        var status = CMSSignerStatus.unsigned
        var trust: SecTrust?
        guard CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &status, &trust, nil) == errSecSuccess,
              status == .valid, let trust, !Self.appleRoots.isEmpty,
              SecTrustSetAnchorCertificates(trust, Self.appleRoots as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess, SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let signer = chain.first else { return false }
        // Apple's Mac provisioning profile signing extension distinguishes this signer
        // from development and distribution identities issued by the same authority.
        let oid = "1.2.840.113635.100.4.11"
        let extensions = SecCertificateCopyValues(signer, [oid] as CFArray, nil) as? [String: Any]
        return extensions?[oid] != nil
    }

    static func covers(_ grant: Any, _ claim: Any) -> Bool {
        if let claim = claim as? [Any] {
            // Apple can grant string-list entitlements such as Associated Domains
            // and iCloud services with a single "*" in the profile.
            if grant as? String == "*" { return claim.allSatisfy { $0 is String } }
            guard let allowed = grant as? [Any] else { return false }
            return claim.allSatisfy { value in allowed.contains { covers($0, value) } }
        }
        if let claim = claim as? [String: Any] {
            guard let allowed = grant as? [String: Any] else { return false }
            return claim.allSatisfy { key, value in allowed[key].map { covers($0, value) } == true }
        }
        if let pattern = grant as? String, let value = claim as? String {
            return pattern == value || (pattern.hasSuffix("*") && value.hasPrefix(pattern.dropLast()))
        }
        guard let lhs = grant as? NSObject, let rhs = claim as? NSObject,
              CFGetTypeID(lhs) == CFGetTypeID(rhs) else { return false }
        return lhs.isEqual(rhs)
    }
}

struct DebugCodeSignature {
    let identifier: String
    let team: String?
    let certificate: Data?
    let entitlements: [String: Any]
    let identity: String
    let code: SecStaticCode
    let codeHash: Data

    init(_ url: URL) throws {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let fields = info as? [String: Any], let identifier = fields[kSecCodeInfoIdentifier as String] as? String,
              let hash = fields[kSecCodeInfoUnique as String] as? Data else {
            throw MacDebugError("Could not read the code signature of \(url.lastPathComponent).")
        }
        self.code = code
        codeHash = hash
        self.identifier = identifier
        team = fields[kSecCodeInfoTeamIdentifier as String] as? String
        entitlements = fields[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        certificate = (fields[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first.map { SecCertificateCopyData($0) as Data }
        if let certificate {
            // codesign accepts the SHA-1 fingerprint as an unambiguous Keychain identity selector.
            identity = Insecure.SHA1.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
        } else if let flags = fields[kSecCodeInfoFlags as String] as? UInt32, SecCodeSignatureFlags(rawValue: flags).contains(.adhoc) {
            identity = "-"
        } else {
            throw MacDebugError("Could not identify the signing identity of \(identifier).")
        }
    }

    /// Xcode can update only embedded.provisionprofile during an incremental build.
    /// Accept that specific resource error for re-sealing, and reject other damage.
    func needsProfileReseal(at profile: URL?) throws -> Bool {
        var failure: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &failure)
        let error = failure?.takeRetainedValue()
        if status == errSecSuccess { return false }
        if status == errSecCSBadResource, let profile, let error,
           let info = CFErrorCopyUserInfo(error) as? [String: Any],
           Set(info.keys).subtracting([kSecCFErrorArchitecture as String]) == [kSecCFErrorResourceAltered as String],
           let altered = info[kSecCFErrorResourceAltered as String] as? [URL], !altered.isEmpty,
           altered.allSatisfy({ $0.absoluteURL.standardizedFileURL == profile.absoluteURL.standardizedFileURL }) {
            return true
        }
        throw MacDebugError("The signature of \(identifier) is invalid. Rebuild the app in Xcode. \(error?.localizedDescription ?? String(status))")
    }
}
