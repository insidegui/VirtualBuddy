# VirtualBuddyGuest support

| Guest | Supported features |
| --- | --- |
| macOS 14 or later with the latest VirtualBuddyGuest | Clipboard sharing and all current guest integration features |
| macOS 13 with a legacy VirtualBuddyGuest | Automatic mounting of shared folders only |
| macOS 12 or earlier | VirtualBuddyGuest is not supported |

Archived guest apps do not support clipboard sharing with the current host, even when selected on a newer guest OS. The host no longer creates a serial connection or handles the legacy protocol. Linux SPICE integration is unchanged.

`GuestAppSupport` applies the same policy to configuration UI, guest installer attachment, and guest communication startup. The latest app’s minimum OS comes from its embedded `LSMinimumSystemVersion`. Unsupported guests skip installer preparation and attachment even if an existing configuration has the guest app enabled.

As with the guest app version picker, OS detection uses restore-image metadata, which records the OS used to create the VM rather than inspecting the running guest. Imported VMs without this metadata use their explicit legacy app selection. Unknown VMs without an override use the latest app. Existing macOS 12 overrides remain recognizable so the UI can flag them as unsupported.

## Updating a running guest

Saved sessions preserve the exact guest installer disk that was attached when saved. Repeatedly saving and resuming does not attach a new installer. The toolbar compares the connected guest's app build with the embedded app and badges compatible updates; guests implementing `guestAppUpdate.v1` also report their code identity so different builds with the same build number can be distinguished. Missing version information is displayed as unknown, not as an available update or an up-to-date app.

The update capability and app report are optional fields of `InitializeGuest`. Older peers keep their existing handshake and clipboard behavior. A host sends update commands only after the guest advertises support. Each operation is scoped to the current session and a unique operation ID, and only one update is accepted at a time.

Remote updates transfer a freshly generated, read-only installer image over VMBridge. The guest verifies its size and SHA-256, mounts it privately, validates the app's full signature against the installed app's designated requirement, and checks its exact identity, minimum OS, and build number. It stages the replacement on the installed app's volume before acknowledging readiness. A separate copy of the signed guest executable runs in installer mode, waits for the old process to exit, and atomically exchanges the app bundles. The previous bundle remains available until the new app launches and reconnects; failed startup rolls back. The host reports success only after a connection reports the expected identity. Interrupted transfers and missing reconnections surface an error and leave manual export available.

Older guests can use **Export Guest Installer…** to save a disk image in an existing shared folder, then open it inside the VM and launch VirtualBuddyGuest. Explicit legacy selections export their selected compatible image rather than the current embedded app. When no shared folder is available, fully shutting down the guest and starting it again attaches the configured installer. Restarting an app, restarting within the running VM, or saving and resuming does not replace that disk.

Automatic installation from `/Volumes/Guest` requires a strictly greater build number. A different code signature with an equal build number never triggers an automatic reinstall from mounted media. Explicit remote updates may install a different signed build with the same build number, and manual installation remains available for local builds. Older saved snapshots still contain their original installed app and memory; restoring one can require updating again.
