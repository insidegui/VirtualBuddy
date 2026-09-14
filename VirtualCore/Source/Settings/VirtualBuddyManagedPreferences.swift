import ManagedPreferencesKit
import OSLog

public enum VirtualBuddyManagedPreferences: ManagedPreferencesNamespace {
    public static let schema = Schema(domain: "codes.rambo.VirtualBuddy", displayName: "VirtualBuddy") {
        Group("Sharing") {
            Preference<Bool>.disableSharedFolders
            Preference<Bool>.disableGuestApp
            Preference<Bool>.disableUSBPassthrough
        }
        Group("Networking") {
            Preference<Bool>.disableBridgedNetworking
        }
        Group("Audio") {
            Preference<Bool>.disableMicrophoneInput
        }
    }

    static var sharedFoldersDisabled: Bool {
        schema.reader().value(for: .disableSharedFolders, default: false)
    }

    static var guestAppDisabled: Bool { schema.reader().value(for: .disableGuestApp, default: false) }
    static var usbPassthroughDisabled: Bool { schema.reader().value(for: .disableUSBPassthrough, default: false) }
    static var bridgedNetworkingDisabled: Bool { schema.reader().value(for: .disableBridgedNetworking, default: false) }
    static var microphoneInputDisabled: Bool { schema.reader().value(for: .disableMicrophoneInput, default: false) }

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

    static let disableGuestApp = Self("DisableGuestApp", title: "Disable Guest App Mounting", default: false) {
        Summary("Prevents VirtualBuddy from mounting its guest app installer disk.")
        DefaultBehavior("The feature follows the VM configuration when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Applies when starting a macOS VM. The guest app mounting control is disabled and the installer disk is omitted, including when constructing a VM for snapshot restoration.")
        Behavior("Does not uninstall, stop, or disable an app already installed in the guest. Existing guest communication and clipboard sharing are unaffected.")
        Behavior("Does not eject an installer disk from an already running VM. Shut down and start the VM to apply this restriction.")
        Options {
            Option(true, "Apply the restriction.")
            Option(false, "Allow the feature.")
        }
        Example(true, "Restrict this feature on managed Macs.")
    }

    static let disableUSBPassthrough = Self("DisableUSBPassthrough", title: "Disable USB Passthrough", default: false) {
        Summary("Prevents attaching host USB accessories to any VM.")
        DefaultBehavior("The feature follows the VM configuration when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Disables USB passthrough controls and blocks automatic and manual attachment. Saved device selections are preserved.")
        Behavior("When a policy change is observed, attached passthrough devices are detached. Detachment failures are logged and shown in the USB menu.")
        Behavior("Emulated USB devices, including virtual keyboards and storage, are unaffected.")
        Options {
            Option(true, "Apply the restriction.")
            Option(false, "Allow the feature.")
        }
        Example(true, "Restrict this feature on managed Macs.")
    }

    static let disableBridgedNetworking = Self("DisableBridgedNetworking", title: "Disable Bridged Networking", default: false) {
        Summary("Prevents VMs from bridging onto host network interfaces.")
        DefaultBehavior("The feature follows the VM configuration when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Saved bridged adapters start disconnected. Their configuration is preserved; users can explicitly select NAT or disable networking.")
        Behavior("When a policy change is observed, active bridged adapters are disconnected. Interface changes and automatic reconnection cannot bypass the restriction.")
        Behavior("NAT networking is unaffected. Restart the VM after removing the restriction to restore saved bridged connections.")
        Options {
            Option(true, "Apply the restriction.")
            Option(false, "Allow the feature.")
        }
        Example(true, "Restrict this feature on managed Macs.")
    }

    static let disableMicrophoneInput = Self("DisableMicrophoneInput", title: "Disable Microphone Input", default: false) {
        Summary("Prevents VM sound devices from receiving host microphone audio.")
        DefaultBehavior("The feature follows the VM configuration when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Disables sound input controls and replaces host audio input with silence when constructing the VM. Sound output and saved settings are preserved.")
        Behavior("Shut down and start running VMs to apply this restriction. Resuming an existing VM configured with host microphone input is denied while restricted; start it again instead.")
        Options {
            Option(true, "Apply the restriction.")
            Option(false, "Allow the feature.")
        }
        Example(true, "Restrict this feature on managed Macs.")
    }
}
