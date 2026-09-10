# Legacy clipboard compatibility

This host-only adapter speaks the serial clipboard protocol used by
VirtualBuddyGuest 1.4 and 2.1. It is independent of VMBridge and VirtualWormhole's
sessions. Only `ClipboardMessage` and the `WHPing`/`WHPong` heartbeat are supported;
defaults import, notifications, and desktop-picture messages are discarded.

Activation uses the embedded guest app's `LSMinimumSystemVersion`, rather than a
hardcoded OS cutoff. The existing restore-image metadata determines the guest OS.
If that metadata is unavailable, a selected legacy guest-app catalog entry counts
as an explicit compatibility declaration only when its entire supported OS range
is below the current minimum. A known supported OS always takes precedence over
an old app selection. Unknown VMs without such a selection use VMBridge. There is
no fallback triggered by connection failure or the installed guest app's age.

As with the existing guest-app picker, restore-image metadata records the OS used
to create the VM; this adapter does not inspect the running guest OS or its disk.

The adapter preserves the old supported clipboard types and PNG preference. It
replies to guest heartbeats and sends the host clipboard when a legacy connection
first becomes active. Clipboard snapshots are coalesced while a write is pending;
frames are never interleaved or cancelled halfway through to send another frame.
Serial input, JSON encoding, and LZMA compression run outside the main actor.
Packet bodies and decompressed payloads are limited to 64 MiB.

Each VM owns its pipes and session. Pause/resume preserves the session; VM stop,
replacement, startup failure, and app termination use the existing awaited guest
communication teardown. Pipe I/O can be interrupted even when the guest stops
reading. Installation and configuration validation do not start a serial session.

`LegacyClipboardTests` checks eligibility, historical wire compatibility,
fragmentation, ignored services, compression, malformed frames, actual pipe I/O,
blocked-write cancellation, clipboard echo suppression, and session restart.
A real archived-app VM smoke test remains unrun: no macOS 12/13 VM was available.
