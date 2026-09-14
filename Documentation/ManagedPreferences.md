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
