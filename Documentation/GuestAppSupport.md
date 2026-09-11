# VirtualBuddyGuest support

| Guest | Supported features |
| --- | --- |
| macOS 14 or later with the latest VirtualBuddyGuest | Clipboard sharing and all current guest integration features |
| macOS 13 with a legacy VirtualBuddyGuest | Automatic mounting of shared folders only |
| macOS 12 or earlier | VirtualBuddyGuest is not supported |

Archived guest apps do not support clipboard sharing with the current host, even when selected on a newer guest OS. The host no longer creates a serial connection or handles the legacy protocol. Linux SPICE integration is unchanged.

`GuestAppSupport` applies the same policy to configuration UI, guest installer attachment, and guest communication startup. The latest app’s minimum OS comes from its embedded `LSMinimumSystemVersion`. Unsupported guests skip installer preparation and attachment even if an existing configuration has the guest app enabled.

As with the guest app version picker, OS detection uses restore-image metadata, which records the OS used to create the VM rather than inspecting the running guest. Imported VMs without this metadata use their explicit legacy app selection. Unknown VMs without an override use the latest app. Existing macOS 12 overrides remain recognizable so the UI can flag them as unsupported.
