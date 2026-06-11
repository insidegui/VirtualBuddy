import Foundation
import OSLog

public extension NSXPCConnection {
    static let virtualInstallationClientAllowList: [String] = [
        kVirtualInstallationServiceName,
        kVirtualBuddyBundleID,
        "codes.rambo.experiment.VMRestoreServicePrototype",
    ]

    func setVirtualInstallationCodeSigningRequirement() {
        /// Disable XPC code signing checks for non-managed releases so open-source contributors don't have to modify configuration files.
        #if !BUILDING_NON_MANAGED_RELEASE
        setCodeSigningRequirement(NSXPCConnection.virtualInstallationCodeSigningRequirementString)
        #endif
    }
}

private extension NSXPCConnection {
    static let virtualInstallationCodeSigningRequirementString: String = {
        let bundleIdentifierClause = virtualInstallationClientAllowList.map {
            """
            info["CFBundleIdentifier"] = "\($0)"
            """
        }.joined(separator: " or ")

        let requirement = String(format: """
        anchor apple generic \
        and certificate leaf[subject.OU] = "%@" \
        and info["CFBundleVersion"] >= "%@" \
        and (%@)
        """, kVirtualInstallationTeamIDForCodeSigningRequirements, kVirtualInstallationProjectVersionForCodeSigningRequirements, bundleIdentifierClause)

        Logger(subsystem: kVirtualInstallationSubsystem, category: "Security")
            .debug("XPC code signing requirement: \(requirement)")

        return requirement
    }()
}
