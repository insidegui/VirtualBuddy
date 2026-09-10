# Guest communication

VirtualWormhole contains VirtualBuddy's application integrations over VMBridge.
`HostGuestSession` belongs to a single `VMInstance`; `GuestHostSession` belongs to
the guest app. Both endpoints use Virtio socket port 51780. Creating a session is
inert; `start()` returns its owned lifetime task and `stop()` cancels and awaits
teardown. Cancel the returned task if its VM owner is being released.

Each connection initializes a fresh application session token. Clipboard updates,
notifications, pictures, and defaults operations are checked against this token.
The host sends its current clipboard after initialization; guest clipboard
observation starts after that snapshot is applied. Later clipboard transfers are
superseded by newer remote revisions or local edits. A shared host coordinator
relays guest edits to the other connected guests unless
`WHDisablePayloadPropagation` is enabled.

Clipboard snapshots and defaults replies fitting VMBridge's encoded-message limit
travel inline. Larger payloads use verified file transfers with a purpose,
session token, and operation ID. A single dispatcher accepts only recognized
offers into temporary files chosen locally. Defaults transfers additionally
require a pending import operation. Failed, cancelled, and superseded transfers
are discarded. Defaults request and transfer waits each have a 30-second deadline.

The guest dashboard uses the app-owned observable session. Defaults import remains
behind `ENABLE_USERDEFAULTS_SYNC`. Guest termination gives the last desktop picture
two seconds, then closes the connection before joining the final send task.

## Verification

Run the VirtualWormhole scheme's tests through Xcode. `GuestSessionTests` exercises
the application layer with injected connections and feature providers; VMBridge's
own suite covers framing and socket transport. Build both VirtualBuddy and
VirtualBuddyGuest, including a guest build with `ENABLE_USERDEFAULTS_SYNC` enabled.

Use a macOS VM with the rebuilt guest app for runtime verification:

1. Confirm `Connected to VirtualBuddy` and host-first clipboard synchronization.
2. Copy supported text and image formats both ways, including an image whose
   encoded data exceeds 8 MiB. Copy new content while a large transfer is pending.
3. Restart the guest app and confirm reconnection, a refreshed desktop thumbnail,
   and one notification registration per name. Exercise lock/unlock notifications.
4. Import a configured defaults domain in a feature-enabled build, checking the
   existing restart confirmation. Interrupt an import by quitting the guest app.
5. Pause/resume, save/restore, request guest shutdown, and force-stop a VM. Verify
   subsequent boots connect and interrupted operations do not affect them.
6. Repeat clipboard and VM-specific events with two guests; disable clipboard
   relay and verify isolation. Disconnect the VM's IP network and verify clipboard
   communication still works over Virtio sockets.

Also launch the guest app outside Xcode: a successful local build can resolve
dynamic package frameworks from DerivedData and conceal missing embedded libraries.
