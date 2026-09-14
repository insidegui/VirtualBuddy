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
- Attempts to add a folder are rejected and logged.
- Existing mappings are ignored when constructing a VM's runtime configuration, including snapshot restoration. The saved VM configuration is preserved.
- When VirtualBuddy observes a preference change, it disconnects the host folder share from existing VM instances. Policy is also checked before and after starting or resuming a VM.

This applies globally to macOS and Linux VMs. Rosetta for Linux remains available because its separate share exposes Apple's translation runtime rather than user-selected host folders. Clipboard sharing, USB passthrough, and networking are separate features and are not controlled by this preference.

After removing the restriction, shut down and start the VM again to restore its saved folder mappings. Missing, false, and incorrectly typed values use the default unrestricted behavior. Deploy a property-list Boolean, not a string or integer.

Policy enforcement messages appear in Console under the `codes.rambo.VirtualCore` subsystem. Configuration and folder-addition messages use the `ManagedPreferences` category; live disconnections use the VM's `VMInstance` category.

## Verification

All five managed preferences are Booleans, with a default of `false`. Missing or incorrectly typed values fall back to that default. VM settings are preserved while a policy overrides their effective behavior.

| Preference | Restriction |
| --- | --- |
| `DisableSharedFolders` | Blocks user-selected host folder shares; Rosetta remains available. |
| `DisableGuestApp` | Omits VirtualBuddy's guest app installer disk on the next VM start. Does not uninstall or stop an already installed guest app, or disable its communication features. |
| `DisableUSBPassthrough` | Blocks automatic and manual host accessory attachment; detaches existing passthrough devices when a policy change is observed. Emulated USB devices are unaffected. |
| `DisableBridgedNetworking` | Leaves bridged adapters disconnected, including on startup and automatic reconnection. NAT remains available and can be explicitly selected by the user. |
| `DisableMicrophoneInput` | Supplies silence instead of host microphone input when constructing the VM. Sound output is unaffected. |

Shut down and start VMs to apply guest-app and microphone restrictions. Virtualization does not expose a public runtime switch for microphone input, so a running VM keeps its current audio configuration until shutdown. Resuming an existing VM configured with microphone input is denied while restricted; cold-start it instead. A snapshot may require a compatible device configuration, particularly if its guest app installer disk is now omitted.

USB detachment failures are logged and shown on the device in the USB menu, where manual detachment remains available. Remove the profile and restart VMs to restore all saved feature selections.

### Generate a signed test profile

From the repository root, run:

```sh
./Scripts/generate_restricted_profile.swift /tmp/VirtualBuddy-Restricted.mobileconfig
```

The script forces all five restrictions to `true` using a system-scoped [managed-preferences payload](https://developer.apple.com/documentation/devicemanagement/managedpreferences). It selects the first trusted, currently valid signing identity from the local keychain search list, signs with SHA-256 CMS, and verifies the signature and payload before writing. Identities need both a certificate and its private key. Private keys remain in the keychain; macOS may request permission to use the selected key. If an identity cannot sign, the script tries the next valid one, and fails if none can sign. Existing output files are not overwritten.

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

For an MDM deployment, verify on an enrolled Mac with an existing shared folder: check disabled controls, a cold VM start, snapshot restoration, and applying the policy while the guest has the share mounted. Remove the policy and restart the VM to confirm its saved mappings are available again.
