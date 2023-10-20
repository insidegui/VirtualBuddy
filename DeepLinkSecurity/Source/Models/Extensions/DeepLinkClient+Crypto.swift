import Cocoa

public extension DeepLinkClient {
    init(auditTokenDescriptor: NSAppleEventDescriptor) throws {
        let attrs = [kSecGuestAttributeAudit: auditTokenDescriptor.data]
        var client: SecCode!

        try checkSecError(SecCodeCopyGuestWithAttributes(nil, attrs as CFDictionary, .default, &client), task: "copy client cs attributes")

        var staticCode: SecStaticCode!
        try checkSecError(SecCodeCopyStaticCode(client, .default, &staticCode), task: "copy client static code")

        var url: CFURL!

        try checkSecError(SecCodeCopyPath(staticCode, .default, &url), task: "copy client path")

        var requirement: SecRequirement!
        try checkSecError(SecCodeCopyDesignatedRequirement(staticCode, .default, &requirement), task: "copy client designated requirement")

        var requirementText: CFString!
        try checkSecError(SecRequirementCopyString(requirement, .default, &requirementText), task: "copy client designated requirement text")

        self.init(url: url as URL, designatedRequirement: requirementText as String)
    }

    init(url: URL) throws {
        var staticCode: SecStaticCode!
        try checkSecError(SecStaticCodeCreateWithPath(url as CFURL, .default, &staticCode), task: "load client static code")

        var requirement: SecRequirement!
        try checkSecError(SecCodeCopyDesignatedRequirement(staticCode, .default, &requirement), task: "copy client designated requirement")

        var requirementText: CFString!
        try checkSecError(SecRequirementCopyString(requirement, .default, &requirementText), task: "copy client designated requirement text")

        self.init(url: url, designatedRequirement: requirementText as String)
    }

    /// Validates the client's static code against the designated requirement,
    /// throwing an error if the signature doesn't match.
    func validate() async throws {
        var requirement: SecRequirement!
        try checkSecError(SecRequirementCreateWithString(designatedRequirement as CFString, .default, &requirement), task: "create client designated requirement")

        var staticCode: SecStaticCode!
        try checkSecError(SecStaticCodeCreateWithPath(url as CFURL, .default, &staticCode), task: "load client static code")

        var errors: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(staticCode, .default, requirement, &errors) == noErr else {
            let errorMessage = errors?.takeUnretainedValue().localizedDescription ?? "Unknown error"
            throw DeepLinkError("Client code signature validation failed with: \(errorMessage)")
        }
    }
}

private func checkSecError(_ closure: @autoclosure () -> OSStatus, task: String) throws {
    let err = closure()

    guard err != noErr else { return }

    let msg = SecCopyErrorMessageString(err, nil) as String?

    throw DeepLinkError("Failed to \(task). Error code \(err): \(msg ?? "<unknown>")")
}

extension SecCSFlags {
    static let `default` = SecCSFlags([])
}
