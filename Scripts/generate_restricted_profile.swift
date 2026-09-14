#!/usr/bin/env swift

import Foundation
import Security

struct ProfileError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == errSecSuccess else {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        throw ProfileError(message: "\(operation): \(detail)")
    }
}

func makeProfile(domain: String) throws -> Data {
    // Keep this list in sync with VirtualBuddyManagedPreferences.schema.
    let restrictions = [
        "DisableSharedFolders": true,
        "DisableGuestApp": true,
        "DisableUSBPassthrough": true,
        "DisableBridgedNetworking": true,
        "DisableMicrophoneInput": true
    ]
    let identifier = "\(domain).restricted-testing"
    let payload: [String: Any] = [
        "PayloadType": "com.apple.ManagedClient.preferences",
        "PayloadVersion": 1,
        "PayloadIdentifier": "\(identifier).preferences",
        "PayloadUUID": UUID().uuidString,
        "PayloadDisplayName": "VirtualBuddy Feature Restrictions",
        "PayloadContent": [domain: ["Forced": [["mcx_preference_settings": restrictions]]]]
    ]
    let profile: [String: Any] = [
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": identifier,
        "PayloadUUID": UUID().uuidString,
        "PayloadDisplayName": "VirtualBuddy — Restrict All Managed Features (Testing)",
        "PayloadDescription": "Disables shared folders, guest app mounting, USB passthrough, bridged networking, and microphone input. Shut down and start VMs after installing or removing this test profile. Already installed guest apps are unaffected.",
        "PayloadScope": "System",
        "PayloadRemovalDisallowed": false,
        "PayloadContent": [payload]
    ]
    return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
}

func sign(_ content: Data, with identity: SecIdentity) throws -> Data {
    var encoder: CMSEncoder?
    try check(CMSEncoderCreate(&encoder), "Create CMS encoder")
    guard let encoder else { throw ProfileError(message: "No CMS encoder was created.") }
    try check(CMSEncoderSetSignerAlgorithm(encoder, kCMSEncoderDigestAlgorithmSHA256), "Select SHA-256")
    try check(CMSEncoderAddSigners(encoder, identity), "Select signing identity")
    try check(CMSEncoderSetHasDetachedContent(encoder, false), "Include profile content")
    try check(content.withUnsafeBytes {
        CMSEncoderUpdateContent(encoder, $0.baseAddress!, $0.count)
    }, "Encode profile")
    var signedContent: CFData?
    try check(CMSEncoderCopyEncodedContent(encoder, &signedContent), "Sign profile")
    guard let signedContent else { throw ProfileError(message: "CMS signing produced no data.") }
    return signedContent as Data
}

func verify(_ signedContent: Data, expectedContent: Data) throws {
    var decoder: CMSDecoder?
    try check(CMSDecoderCreate(&decoder), "Create CMS decoder")
    guard let decoder else { throw ProfileError(message: "No CMS decoder was created.") }
    try check(signedContent.withUnsafeBytes {
        CMSDecoderUpdateMessage(decoder, $0.baseAddress!, $0.count)
    }, "Decode signed profile")
    try check(CMSDecoderFinalizeMessage(decoder), "Finalize signed profile")
    var status = CMSSignerStatus.unsigned
    // Trust was evaluated when selecting the identity; verify the CMS signature here.
    try check(CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &status, nil, nil), "Verify signature")
    guard status == .valid else { throw ProfileError(message: "CMS signature verification failed.") }
    var decoded: CFData?
    try check(CMSDecoderCopyContent(decoder, &decoded), "Read signed payload")
    guard let decoded, decoded as Data == expectedContent else {
        throw ProfileError(message: "Signed content does not match the generated profile.")
    }
}

func signWithFirstValidIdentity(_ content: Data) throws -> (Data, String) {
    // Search the user's normal keychain search list. Private keys stay in the keychain.
    let query: [String: Any] = [
        kSecClass as String: kSecClassIdentity,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnRef as String: true
    ]
    var result: CFTypeRef?
    try check(SecItemCopyMatching(query as CFDictionary, &result), "Find local signing identities")
    guard let identities = result as? [SecIdentity], !identities.isEmpty else {
        throw ProfileError(message: "No certificate with a private key was found in the local keychains.")
    }
    for identity in identities {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { continue }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else { continue }
        try check(SecTrustSetNetworkFetchAllowed(trust, false), "Configure local certificate validation")
        // Reject expired, not-yet-valid, or untrusted certificates.
        guard SecTrustEvaluateWithError(trust, nil) else { continue }
        let name = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unnamed certificate"
        FileHandle.standardError.write(Data("Signing with \(name). macOS may request access to this key.\n".utf8))
        do {
            let signed = try sign(content, with: identity)
            try verify(signed, expectedContent: content)
            return (signed, name)
        } catch {
            FileHandle.standardError.write(Data("Skipping \(name): \(error.localizedDescription)\n".utf8))
        }
    }
    throw ProfileError(message: "No valid local identity could sign the profile. Add a trusted, unexpired signing certificate and its private key to your keychain.")
}

func run() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] {
        print("Usage: generate_restricted_profile.swift [--domain bundle.identifier] [output.mobileconfig]")
        print("Signs with the first valid identity in the local keychain search list. Does not install the profile or overwrite an existing file.")
        return
    }
    var domain = "codes.rambo.VirtualBuddy"
    if arguments.first == "--domain" {
        guard arguments.count >= 2, !arguments[1].isEmpty, !arguments[1].hasPrefix("-") else {
            throw ProfileError(message: "--domain requires a preference domain.")
        }
        domain = arguments[1]
        arguments.removeFirst(2)
    }
    guard arguments.count <= 1, arguments.first?.hasPrefix("-") != true else {
        throw ProfileError(message: "Invalid arguments. Use --help for usage.")
    }
    let output = URL(fileURLWithPath: arguments.first ?? "VirtualBuddy-Restricted.mobileconfig")
    guard !FileManager.default.fileExists(atPath: output.path) else {
        throw ProfileError(message: "Output already exists: \(output.path)")
    }
    let (signed, signer) = try signWithFirstValidIdentity(makeProfile(domain: domain))
    try signed.write(to: output, options: .withoutOverwriting)
    print("Signed with: \(signer)")
    print("Created: \(output.path)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
