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
        Group("Service Tunnels") {
            Preference<Bool>.disableServiceTunnels
            Preference<Bool>.disableServiceTunnelsToHostServices
            Preference<Bool>.disableServiceTunnelsToGuestServices
            Preference<Bool>.disableServiceTunnelUnixSockets
            Preference<Bool>.disableServiceTunnelTCPPorts
            Preference<Bool>.disableServiceTunnelRequests
            Preference<[String]>.serviceTunnelAllowedHostPorts
            Preference<[String]>.serviceTunnelDeniedHostPorts
            Preference<[String]>.serviceTunnelAllowedHostSocketPaths
            Preference<[String]>.serviceTunnelDeniedHostSocketPaths
        }
        Group("Audio") {
            Preference<Bool>.disableMicrophoneInput
        }
        Group("Provisioning") {
            Preference<Bool>.disableProvisioningRemoteLogin
            Preference<Bool>.disableProvisioningAutomaticLogin
        }
        Group("Developer") {
            Preference<Bool>.disableDeveloperFeatures
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
    static let disableDeveloperFeatures = Self("DisableDeveloperFeatures", title: "Disable Developer Features", default: false) {
        Summary("Prevents users from enabling developer features or starting Xcode debug runs in virtual machines.")
        DefaultBehavior("When absent or false, VirtualBuddy uses the user's Developer Features setting. Invalid values fall back to false.")
        Behavior("Locks the Developer Features switch off, hides Xcode debugging setup, and blocks new debug runs from existing schemes.")
        Behavior("Users can still delete cached symbols. Removing the restriction restores the user's saved setting.")
        Options {
            Option(true, "Disable developer features.")
            Option(false, "Allow users to choose whether to enable developer features.")
        }
    }

    static let disableProvisioningRemoteLogin = Self("DisableProvisioningRemoteLogin", title: "Disable Provisioning Remote Login", default: false) {
        Summary("Prevents VirtualBuddy from enabling remote login (SSH) during macOS guest provisioning.")
        DefaultBehavior("The saved provisioning setting is used when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Disables the provisioning control and prevents remote login from being enabled during provisioning. The saved selection is preserved.")
        Behavior("Does not change remote login in an existing guest or prevent it from being enabled inside the guest.")
        Options {
            Option(true, "Disable remote login during provisioning.")
            Option(false, "Allow remote login during provisioning.")
        }
    }

    static let disableProvisioningAutomaticLogin = Self("DisableProvisioningAutomaticLogin", title: "Disable Provisioning Automatic Login", default: false) {
        Summary("Prevents VirtualBuddy from enabling automatic login during macOS guest provisioning.")
        DefaultBehavior("The saved provisioning setting is used when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Disables the provisioning control and prevents automatic login from being enabled during provisioning. The saved selection is preserved.")
        Behavior("Does not change automatic login in an existing guest or prevent it from being enabled inside the guest.")
        Options {
            Option(true, "Disable automatic login during provisioning.")
            Option(false, "Allow automatic login during provisioning.")
        }
    }

    static let disableSharedFolders = Self("DisableSharedFolders", title: "Disable Shared Folders", default: false) {
        Summary("Disables host folder sharing for all virtual machines.")
        Discussion("Deploy this Boolean in the VirtualBuddy preference domain using an MDM configuration profile. It applies to macOS and Linux guests, including existing virtual machines.")
        DefaultBehavior("Shared folders are available when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Disables shared folder controls and rejects attempts to edit live folder mappings.")
        Behavior("Ignores saved folder mappings when starting or restoring a VM. Mappings remain saved so they can be used after the restriction is removed.")
        Behavior("When a policy change is observed, shared folders are disconnected from running VMs. When the restriction is removed, the current session’s folder mappings are shared again.")
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

    static let disableServiceTunnels = Self("DisableServiceTunnels", title: "Disable Service Tunnels", default: false) {
        Summary("Disables service tunnels between this Mac and all virtual machines.")
        Discussion("Service tunnels forward loopback TCP ports and Unix sockets between the host and a macOS guest. Use the other service tunnel preferences instead of this one to restrict only part of the feature.")
        DefaultBehavior("Service tunnels are available when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Saved tunnels don't start, and requests from virtual machines are rejected. Tunnels remain saved so they can be used after the restriction is removed.")
        Behavior("When a policy change is observed, running tunnels are stopped and their connections closed. When the restriction is removed, saved tunnels start again.")
        Options {
            Option(true, "Service tunnels are unavailable.")
            Option(false, "Service tunnels are available.")
        }
        Example(true, "Disable service tunnels on managed Macs.")
    }

    static let disableServiceTunnelsToHostServices = Self("DisableServiceTunnelsToHostServices", title: "Disable Service Tunnels to Host Services", default: false) {
        Summary("Prevents virtual machines from reaching services on this Mac through service tunnels.")
        Discussion("This is the direction in which a virtual machine gains access to something on the host, such as a local database, a development server or an agent socket.")
        DefaultBehavior("Tunnels to host services are available when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Tunnels whose service runs on the host don't start and can't be requested by virtual machines. Tunnels to services in virtual machines are unaffected.")
        Options {
            Option(true, "Virtual machines can't reach host services through tunnels.")
            Option(false, "Allow tunnels to host services.")
        }
        Example(true, "Only let this Mac reach services in virtual machines.")
    }

    static let disableServiceTunnelsToGuestServices = Self("DisableServiceTunnelsToGuestServices", title: "Disable Service Tunnels to Guest Services", default: false) {
        Summary("Prevents this Mac from reaching services in virtual machines through service tunnels.")
        Discussion("In this direction the tunnel listens on a loopback port or socket path on the host, and apps on the host that connect to it reach a service in the virtual machine.")
        DefaultBehavior("Tunnels to guest services are available when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Tunnels whose service runs in the virtual machine don't start and can't be requested by virtual machines. Tunnels to host services are unaffected.")
        Options {
            Option(true, "This Mac can't reach guest services through tunnels.")
            Option(false, "Allow tunnels to guest services.")
        }
    }

    static let disableServiceTunnelUnixSockets = Self("DisableServiceTunnelUnixSockets", title: "Disable Unix Sockets in Service Tunnels", default: false) {
        Summary("Prevents service tunnels from using Unix sockets.")
        DefaultBehavior("Unix sockets are available when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Tunnels with a Unix socket on either side don't start and can't be requested by virtual machines. Tunnels between TCP ports are unaffected.")
        Options {
            Option(true, "Tunnels can't use Unix sockets.")
            Option(false, "Allow Unix sockets.")
        }
    }

    static let disableServiceTunnelTCPPorts = Self("DisableServiceTunnelTCPPorts", title: "Disable TCP Ports in Service Tunnels", default: false) {
        Summary("Prevents service tunnels from using TCP ports.")
        DefaultBehavior("TCP ports are available when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Tunnels with a TCP port on either side don't start and can't be requested by virtual machines. Tunnels between Unix sockets are unaffected.")
        Options {
            Option(true, "Tunnels can't use TCP ports.")
            Option(false, "Allow TCP ports.")
        }
    }

    static let disableServiceTunnelRequests = Self("DisableServiceTunnelRequests", title: "Disable Service Tunnel Requests", default: false) {
        Summary("Prevents virtual machines from asking for service tunnels.")
        DefaultBehavior("Virtual machines can request tunnels, which a user on this Mac has to allow, when this preference is absent or false. Invalid values fall back to false.")
        Behavior("Requests from VirtualBuddyGuest are rejected and never shown. Tunnels can still be added in the virtual machine's settings on this Mac.")
        Options {
            Option(true, "Virtual machines can't request tunnels.")
            Option(false, "Allow virtual machines to request tunnels.")
        }
    }
}

public extension ManagedPreference where Namespace == VirtualBuddyManagedPreferences, Value == [String] {
    static let serviceTunnelAllowedHostPorts = Self("ServiceTunnelAllowedHostPorts", as: [String].self, title: "Allowed Host Ports for Service Tunnels") {
        Summary("Limits the TCP ports on this Mac that service tunnels can use to the listed ones.")
        Discussion("Each entry is a port such as \"8080\" or a range such as \"8000-8099\". The list applies to ports on this Mac in both directions: the port a tunnel listens on, and the port of a host service a virtual machine reaches. Ports inside virtual machines aren't restricted.")
        DefaultBehavior("Every host port can be used when this preference is absent.")
        Behavior("Tunnels using a host port that isn't listed don't start and can't be requested by virtual machines. An empty list allows no host port.")
        Behavior("A port that's also in ServiceTunnelDeniedHostPorts is not allowed.")
        Note("A value that isn't a list, and entries that aren't ports or ranges, allow nothing. Integers are accepted in place of strings.")
        Example(["5432", "8000-8099"], "Only allow tunnels to use host port 5432 and ports 8000 to 8099.")
    }

    static let serviceTunnelDeniedHostPorts = Self("ServiceTunnelDeniedHostPorts", as: [String].self, title: "Denied Host Ports for Service Tunnels") {
        Summary("Prevents service tunnels from using the listed TCP ports on this Mac.")
        Discussion("Entries have the same form and apply to the same ports as in ServiceTunnelAllowedHostPorts.")
        DefaultBehavior("No host port is denied when this preference is absent.")
        Behavior("Tunnels using a listed host port don't start and can't be requested by virtual machines.")
        Note("A value that isn't a list, and entries that aren't ports or ranges, deny every host port. Integers are accepted in place of strings.")
        Example(["22", "5900-5999"], "Keep tunnels away from SSH and screen sharing on this Mac.")
    }

    static let serviceTunnelAllowedHostSocketPaths = Self("ServiceTunnelAllowedHostSocketPaths", as: [String].self, title: "Allowed Host Socket Paths for Service Tunnels") {
        Summary("Limits the Unix socket paths on this Mac that service tunnels can use to the listed ones.")
        Discussion("Each entry is the full path of a socket, or the path of a folder followed by a slash for everything inside that folder. A leading ~ stands for the home folder of the user running VirtualBuddy. The list applies to socket paths on this Mac in both directions: the path a tunnel listens on, and the socket of a host service a virtual machine reaches. Socket paths inside virtual machines aren't restricted.")
        DefaultBehavior("Every host socket path can be used when this preference is absent.")
        Behavior("Tunnels using a host socket path that isn't listed don't start and can't be requested by virtual machines. An empty list allows no host socket path.")
        Behavior("Paths are compared after following links, so a path can't be reached by another name for the same location. A path that also matches ServiceTunnelDeniedHostSocketPaths is not allowed.")
        Note("A value that isn't a list, and entries that aren't absolute paths, allow nothing.")
        Example(["~/Library/Application Support/Tunnels/"], "Only allow tunnels to use sockets in one folder of the user's Library.")
    }

    static let serviceTunnelDeniedHostSocketPaths = Self("ServiceTunnelDeniedHostSocketPaths", as: [String].self, title: "Denied Host Socket Paths for Service Tunnels") {
        Summary("Prevents service tunnels from using the listed Unix socket paths on this Mac.")
        Discussion("Entries have the same form and apply to the same paths as in ServiceTunnelAllowedHostSocketPaths.")
        DefaultBehavior("No host socket path is denied when this preference is absent.")
        Behavior("Tunnels using a listed host socket path, or a path inside a listed folder, don't start and can't be requested by virtual machines.")
        Note("A value that isn't a list, and entries that aren't absolute paths, deny every host socket path.")
        Example(["/var/run/docker.sock", "~/.ssh/"], "Keep tunnels away from the Docker socket and from anything in the user's .ssh folder.")
    }
}
