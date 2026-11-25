# Managed preferences

VirtualBuddy supports administrator policies delivered through MDM-managed preferences. The production preference domain is `codes.rambo.VirtualBuddy`.

Open **Settings → Virtualization → Managed Preferences…** for the reference generated from the app's preference declarations. This view can export Markdown documentation and a ProfileManifests-compatible plist. The exported manifest describes the preferences to management tools; it is not an installable configuration profile.

## Disable shared folders

Deploy the following setting in a custom settings payload for the VirtualBuddy preference domain:

```xml
<key>DisableSharedFolders</key>
<true/>
```

`DisableSharedFolders` is a Boolean, defaulting to `false`. When enabled:

- Shared folder controls are disabled with an organization policy message.
- Attempts to add a folder or edit live folder mappings are rejected.
- Existing mappings are ignored when constructing a VM's runtime configuration, including when a saved session is resumed. The saved VM configuration is preserved. Shared folders are live resources, so a saved session doesn't preserve or roll back their contents.
- When VirtualBuddy observes a preference change, it disconnects the host folder share from existing VM instances. Policy is also checked before and after starting or resuming a VM.

This applies globally to macOS and Linux VMs. Rosetta for Linux remains available because its separate share exposes Apple's translation runtime rather than user-selected host folders. Clipboard sharing, USB passthrough, and networking are separate features and are not controlled by this preference.

After removing the restriction, the current session’s folder mappings are shared again automatically. Missing, false, and incorrectly typed values use the default unrestricted behavior. Deploy a property-list Boolean, not a string or integer.

Policy enforcement messages appear in Console under the `codes.rambo.VirtualCore` subsystem. Configuration and folder-addition messages use the `ManagedPreferences` category; live disconnections use the VM's `VMInstance` category.

## Disable developer features

To prevent users from enabling developer features, deploy this Boolean in the `codes.rambo.VirtualBuddy` preference domain:

```xml
<key>DisableDeveloperFeatures</key>
<true/>
```

The profile locks **Settings → Developer → Enable Developer Features** off, including on Macs with Xcode installed. VirtualBuddy hides **Set Up Xcode Debugging…** and rejects new debug runs from existing schemes. Attached debugging sessions can finish, and users can still delete cached symbols in the Developer tab. Removing the restriction restores the user's saved choice.

## Restrict service tunnels

[Service tunnels](ServiceTunnels.md) forward loopback TCP ports and Unix sockets between the host and a macOS guest. A profile can turn the feature off, turn off parts of it, or limit the host ports and socket paths it can use. All of these preferences go in the `codes.rambo.VirtualBuddy` preference domain and can be combined.

To turn the feature off entirely:

```xml
<key>DisableServiceTunnels</key>
<true/>
```

To restrict part of it, use any of these Booleans instead. Each defaults to `false`.

| Preference | Restriction |
| --- | --- |
| `DisableServiceTunnelsToHostServices` | Virtual machines can't reach services on the host. This is the direction that gives a virtual machine access to something on the Mac. |
| `DisableServiceTunnelsToGuestServices` | The host can't reach services in virtual machines. |
| `DisableServiceTunnelUnixSockets` | Tunnels can't have a Unix socket on either side. |
| `DisableServiceTunnelTCPPorts` | Tunnels can't have a TCP port on either side. |
| `DisableServiceTunnelRequests` | Virtual machines can't ask for tunnels. Tunnels can still be added in the virtual machine's settings on the host. |

Four lists control which ports and socket paths **on the host** tunnels can use. They apply in both directions: to the address a tunnel listens on, and to the host service a virtual machine reaches. Ports and paths inside virtual machines aren't restricted.

| Preference | Entries |
| --- | --- |
| `ServiceTunnelAllowedHostPorts` | When present, only these host ports can be used. An empty list allows none. |
| `ServiceTunnelDeniedHostPorts` | These host ports can't be used. |
| `ServiceTunnelAllowedHostSocketPaths` | When present, only these host socket paths can be used. An empty list allows none. |
| `ServiceTunnelDeniedHostSocketPaths` | These host socket paths can't be used. |

A port entry is a port (`8080`) or a range (`8000-8099`). A path entry is the full path of a socket, or the path of a folder followed by a slash for everything inside it. A leading `~` stands for the home folder of the user running VirtualBuddy, so one profile works for every account. Paths are compared after following links, so `/tmp/agent.sock` and `/private/tmp/agent.sock` are the same path to the policy. An entry in a denied list takes precedence over the allowed list.

For example, to let virtual machines reach only a database and a range of development ports on the host, while keeping every tunnel away from the user's SSH folder:

```xml
<key>ServiceTunnelAllowedHostPorts</key>
<array>
    <string>5432</string>
    <string>8000-8099</string>
</array>
<key>ServiceTunnelDeniedHostSocketPaths</key>
<array>
    <string>~/.ssh/</string>
</array>
```

When a restriction applies:

- Tunnels it doesn't allow don't start. They stay saved and approved, are marked as blocked in the virtual machine's settings, and start again when the restriction is removed.
- New tunnels it doesn't allow can't be added in settings, and requests for them from a virtual machine are rejected without being shown. The virtual machine is told only that the organization doesn't allow the tunnel.
- When VirtualBuddy observes a preference change, it stops running tunnels that are no longer allowed and closes their connections, and starts the ones that are allowed again. Virtual machines don't need to be restarted.

The lists fail closed. A value that isn't an array, or an entry that isn't a port, a range or an absolute path, allows nothing in an allowed list and denies everything in a denied list. Integers are accepted for ports. The Booleans behave like the other restrictions: missing and incorrectly typed values mean unrestricted.

## Verification

Apart from the service tunnel lists described above, all managed preferences are Booleans, with a default of `false`. Missing or incorrectly typed values fall back to that default. Saved settings are preserved while a policy overrides their effective behavior.

| Preference | Restriction |
| --- | --- |
| `DisableSharedFolders` | Blocks user-selected host folder shares; Rosetta remains available. |
| `DisableGuestApp` | Omits VirtualBuddy's guest app installer disk on the next VM start. Does not uninstall or stop an already installed guest app, or disable its communication features. |
| `DisableUSBPassthrough` | Blocks automatic and manual host accessory attachment; detaches existing passthrough devices when a policy change is observed. Emulated USB devices are unaffected. |
| `DisableBridgedNetworking` | Leaves bridged adapters disconnected, including on startup and automatic reconnection. NAT remains available and can be explicitly selected by the user. |
| `DisableMicrophoneInput` | Supplies silence instead of host microphone input when constructing the VM. Sound output is unaffected. |
| `DisableProvisioningRemoteLogin` | Prevents VirtualBuddy from enabling remote login (SSH) during macOS guest provisioning. |
| `DisableProvisioningAutomaticLogin` | Prevents VirtualBuddy from enabling automatic login during macOS guest provisioning. |
| `DisableDeveloperFeatures` | Locks developer features off and blocks Xcode debugging setup and new debug runs. |
| `DisableServiceTunnels` and the other service tunnel preferences | Stops service tunnels, or the part of the feature each one names, as described under [Restrict service tunnels](#restrict-service-tunnels). |

The provisioning restrictions apply when VirtualBuddy creates a macOS guest account. They do not modify existing guest settings or prevent someone from changing those settings inside the guest. Saved provisioning selections are preserved and become available again if the restriction is removed before provisioning.

Shut down and start VMs to apply guest-app and microphone restrictions. Virtualization does not expose a public runtime switch for microphone input, so a running VM keeps its current audio configuration until shutdown. Resuming a saved session of a VM configured with microphone input is denied while restricted. Discard the saved session, which loses its running state, and cold-start the VM instead. A saved session also needs the guest app installer disk it was saved with: if the policy now omits that disk, resuming is blocked with an explanation.

USB detachment failures are logged and shown on the device in the USB menu, where manual detachment remains available. Remove the profile and restart VMs to restore all saved feature selections.

### Generate a signed test profile

From the repository root, run:

```sh
./Scripts/generate_restricted_profile.swift /tmp/VirtualBuddy-Restricted.mobileconfig
```

The script forces all restrictions to `true` using a system-scoped [managed-preferences payload](https://developer.apple.com/documentation/devicemanagement/managedpreferences). It selects the first trusted, currently valid signing identity from the local keychain search list, signs with SHA-256 CMS, and verifies the signature and payload before writing. Identities need both a certificate and its private key. Private keys remain in the keychain; macOS may request permission to use the selected key. If an identity cannot sign, the script tries the next valid one, and fails if none can sign. Existing output files are not overwritten.

For a build with a different bundle identifier:

```sh
./Scripts/generate_restricted_profile.swift --domain your.bundle.identifier /tmp/VirtualBuddy-Restricted.mobileconfig
```

The script creates the profile without installing it. Install it manually through System Settings or MDM, then remove it after testing. The certificate must also be trusted on the test Mac for the profile to be shown as verified. Keep the script's restriction list in sync when adding managed features.

### Local defaults

For local development, the reader also accepts ordinary defaults in the running app's preference domain. For the production bundle identifier:

```sh
defaults write codes.rambo.VirtualBuddy DisableSharedFolders -bool true
```

Remove this local override after checking the behavior:

```sh
defaults delete codes.rambo.VirtualBuddy DisableSharedFolders
```

An MDM-forced value takes precedence over user defaults. Builds with a custom bundle identifier read that build's own defaults domain.

For an MDM deployment, verify on an enrolled Mac with an existing shared folder: check disabled controls, a cold VM start, resuming a saved session, and applying the policy while the guest has the share mounted. Remove the policy and restart the VM to confirm its saved mappings are available again.
