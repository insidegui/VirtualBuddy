import DistBuddy

/// Describes how VirtualBuddy is built, notarized and packaged for distribution.
/// Run `distbuddy` in this directory to produce a notarized disk image.
/// See https://github.com/insidegui/distbuddy for the full configuration reference.
/// NOTE: this tool is not currently open-source, this configuration is only needed
/// for distribution packaging and notarization, use Xcode to run your own builds locally.
@main
struct VirtualBuddyDistribution: DistributionConfiguration {
    var distribution: Distribution {
        Distribution(
            app: XcodeArchive(
                scheme: "VirtualBuddy (Managed)",
                teamID: "8C7439RJLG",
                allowProvisioningUpdates: false
            ),
            notarization: .notaryTool(keychainProfile: "NOTARYTOOLRAMBO"),
            diskImage: StandardDiskImage(),
            outputDirectory: "Releases"
        )
        
        Distribution(
            app: XcodeArchive(
                scheme: "VirtualBuddy (Managed - Beta)",
                teamID: "8C7439RJLG",
                allowProvisioningUpdates: false
            ),
            notarization: .notaryTool(keychainProfile: "NOTARYTOOLRAMBO"),
            diskImage: StandardDiskImage(),
            outputDirectory: "Releases",
            train: "beta"
        )
    }
}
