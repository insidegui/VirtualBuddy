import ManagedPreferencesKit
import OSLog

public enum VirtualBuddyManagedPreferences: ManagedPreferencesNamespace {
    public static let schema = Schema(domain: "codes.rambo.VirtualBuddy", displayName: "VirtualBuddy") {
        Group("Sharing") {
            Preference<Bool>.disableSharedFolders
        }
    }

    static var sharedFoldersDisabled: Bool {
        schema.reader().value(for: .disableSharedFolders, default: false)
    }

    static let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "ManagedPreferences")
}

public extension ManagedPreference where Namespace == VirtualBuddyManagedPreferences, Value == Bool {
    static let disableSharedFolders = Self("DisableSharedFolders", title: "Disable Shared Folders", default: false) {
        Summary("Disables host folder sharing for all virtual machines.")
        Discussion("Deploy this Boolean in the VirtualBuddy preference domain using an MDM configuration profile. It applies to macOS and Linux guests, including existing virtual machines.")
        DefaultBehavior("Shared folders are available when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Disables shared folder controls and rejects attempts to add folders, with a policy message in the log.")
        Behavior("Ignores saved folder mappings when starting or restoring a VM. Mappings remain saved so they can be used after the restriction is removed.")
        Behavior("When a policy change is observed, shared folders are disconnected from running VMs. Restart the VM after removing the restriction to share its folders again.")
        Behavior("Rosetta for Linux is unaffected: its separate share exposes Apple's translation runtime, not user-selected host folders.")
        Options {
            Option(true, "Shared folders are unavailable.")
            Option(false, "Shared folders are available.")
        }
        Example(true, "Disable host folder sharing on managed Macs.")
    }
}
