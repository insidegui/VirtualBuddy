# Guest communication

VirtualWormhole contains VirtualBuddy's application integrations over VMBridge.
`HostGuestSession` belongs to a single `VMInstance`; `GuestHostSession` belongs to
the guest app. Both endpoints use Virtio socket port 51780. Creating a session is
inert; `start()` returns its owned lifetime task and `stop()` cancels and awaits
teardown. Cancel the returned task if its VM owner is being released.

Each connection initializes a fresh application session token. Clipboard updates,
notifications, pictures, system information, and defaults operations are checked against this token.
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
behind `ENABLE_USERDEFAULTS_SYNC`. Guest termination gives the final desktop picture
and system information snapshots a shared two-second deadline, then closes the
connection before joining the final send tasks.

## Service architecture

`GuestSessionEngine` owns the transport run, initialization exchange, observable
connection state, and service lifecycle. Its endpoint is explicit; services do not
infer host/guest identity from clipboard configuration. `GuestServiceContext`
provides the connection, current application token, endpoint, and request timeout.

Each service is a separate `GuestService` subclass under `Source/Services`:

- `ClipboardGuestService`: snapshots, revisions, polling, large clipboard
  transfers, and registration with the shared host clipboard coordinator.
- `NotificationsGuestService`: notification negotiation, observation, and delivery.
- `DesktopPictureGuestService`: initial and termination snapshots and delivery.
- `SystemInformationGuestService`: session-scoped, revision-ordered system reports,
  lifecycle observation, and periodic refresh.
- `AppearanceGuestService`: guest appearance reports and host-to-guest appearance
  commands, with optional automatic synchronization from the host.
- `DefaultsGuestService`: export/import requests, pending imports, deadlines,
  and defaults file transfers.

Feature providers are assembled at session construction, but each service receives
only its own dependencies. Public session methods and callbacks forward to the
appropriate service; the existing app-facing API is unchanged.

### Adding a service

1. Define its `VMMessage` payloads. Keep existing wire type names and Codable
   representations stable: VMBridge's default message ID is the type name.
2. Add a `GuestService` subclass with its own dependencies and state. Override
   `subscriptions()` to obtain typed message or request streams synchronously and
   return their asynchronous consumers. `GuestConnection.requests(of:reply:)`
   supplies typed reply closures without changes to the connection adapter.
3. Construct and include the service in the engine's `services` list. Expose any
   app-facing operations through the appropriate public session wrapper.
4. Use `activate(notifications:)` for work following initialization. Validate
   endpoint and session on incoming messages. Capture the token for asynchronous
   work and call `requireSession` after suspension before applying its result.
5. Use `schedule` for owned background work. Override `invalidate()` (calling
   `super`) to remove observers, reset state, and cancel/finish service-specific
   waiters. Override `drain()` if the service owns additional tasks. Invalidation
   is synchronous on disconnect; final draining happens after transport closes,
   so a blocked send cannot deadlock shutdown. Do not drain during reconnection.
6. For bulk data, add a stable `TransferIdentity.Purpose`, override
   `transferPurpose` and `receiveOffer`, and validate operation identity before
   accepting into a locally selected temporary file. There is one dispatcher;
   unknown purposes and stale tokens are rejected. Clean up files on every exit.

Subscriptions and service state use MainActor isolation because the existing
features interact with AppKit and app-observed state. Keep expensive new feature
work off that actor where appropriate. A stream ending unexpectedly ends the
connection run, so subscription consumers must remain alive until cancellation.

### Compatibility

This refactor preserves port 51780, initialization request/reply fields, message
IDs and payloads, notification names, transfer metadata, and the VMBridge package
version. No new negotiation is required from existing VMBridge guests. Frozen
wire fixtures in `GuestWireCompatibilityTests` protect those representations.
Archived serial-protocol guests retain their existing shared-folder-only support;
see `Documentation/GuestAppSupport.md`.

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

## Guest appearance

Hosts advertise `appearance.v1` in the initialization reply. Compatible guests
report their current appearance after initialization and when macOS posts
`AppleInterfaceThemeChangedNotification`. The first report enables the host's
appearance controls; older hosts receive no new messages, and older guests are
not sent appearance commands. Reports and command acknowledgements share a
session-scoped revision sequence so late replies cannot overwrite newer reports.

The connection status popover provides Dark Mode and Automatically Sync with Host.
Sync is persisted per VM as `automaticallySyncGuestAppearance`, defaults to false
when absent, and immediately applies the host's appearance when enabled or when
the guest reconnects. Observation belongs to the service, so closing the popover
does not stop synchronization. Manual control is disabled while sync is enabled.
Guest appearance changes update the displayed toggle but never change the host
or other guests. Disabling sync leaves the guest's current appearance intact.

System appearance uses the same `SLSGetAppearanceThemeLegacy` and
`SLSSetAppearanceThemeLegacy` SPI as DarkModeBuddy, dynamically resolved from
SkyLight. Missing SPI disables appearance control without breaking other services.
Only the guest endpoint applies incoming commands. Requests are serialized and
rapid host changes coalesce; failures are shown in the popover. Observers and
pending work are removed on disconnection.

For runtime verification, install the rebuilt guest app and check manual light/dark
switching, enabling sync while the appearances differ, host appearance changes with
the popover closed, guest-only appearance changes, disabling sync, and reconnection.
Confirm the preference survives restarting VirtualBuddy, and repeat with two VMs
with different sync preferences. An older guest should show disabled controls and
the update guidance. Automated session tests use injected appearance providers and
never change the test Mac's appearance.

## Guest system information

Hosts advertise `systemInformation.v1` in the optional `InitializeGuestReply.capabilities`
field. New guests do not send system reports to older hosts; older guests ignore the
new reply field. Existing wire payload fixtures remain unchanged.

The guest collects macOS version/build, kernel version, computer name, architecture,
processor count, physical memory, boot time, and guest app version/build. SIP is read
using the read-only `/usr/bin/csrutil status` command with a fixed locale and a one-second
cancellable deadline; custom output is retained verbatim and unrecognized or unavailable
status is displayed as Unknown. No private API or privilege elevation is needed.

A report is sent after each connection handshake, every five minutes, when the app
becomes active, when the workspace session becomes active, after wake, before sleep
or power-off, and during the app's bounded termination preparation. Event refreshes
are coalesced while one is in flight. Observers and periodic work are removed on
disconnect. Abrupt power loss and forced VM stops can only retain the preceding report.

The host atomically writes `.vbdata/GuestSystemInfo.plist` inside the reporting VM's
bundle. The versioned record includes a host-generated receipt timestamp; it does not
modify configuration or installation metadata. Recovery boots do not replace the
installed system's report. Missing, corrupt, and unsupported-version records are ignored.
The library's existing plist observation refreshes the summary and open Get Info windows.
Right-click a VM and choose Get Info to inspect or copy the full report while offline.

Verification: run VirtualWormhole tests and the VirtualCore
`GuestSystemInformationStorageTests` through Xcode. In a VM, run the rebuilt guest,
check the library and Get Info, rename the guest computer and activate the guest app,
then shut down and reopen the host. Confirm the report and timestamp persist. Repeat
with SIP enabled, disabled, and a custom configuration; compare SIP Details with
`csrutil status` inside that guest. Old guest releases show the no-report state until updated.
