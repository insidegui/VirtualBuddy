# Service Tunnels

In the host's VM Settings → Service Tunnels, add a tunnel by choosing where the service
runs and where it should be reachable from. For example, a service running on the Guest at
`127.0.0.1:3000` can be accessed from the Host at `127.0.0.1:8080`.
A browser on the host can then reach the guest service while the VM's network adapter
is disconnected. Both endpoints support IPv4 loopback, IPv6 loopback, and Unix
stream sockets. For a Unix listener, choose an unused socket path. When the tunnel
starts, VirtualBuddy creates any missing directories with access limited to the
current account. An existing socket directory must be owned by that account with
group and other write access disabled. Every folder enclosing it has to belong to
that account or to the system, both along the path as written and along the
location it leads to through any links. A listener removes its socket file
when the tunnel stops. If the app or the machine went down before that could happen,
the next listener for that path replaces the file, as long as it's still the socket
VirtualBuddy created there and nothing is listening on it. Any other existing file
is left alone and the tunnel reports the address as in use. The service creates its own destination socket.
A destination socket is held to the same rule about who owns its path, and the
service listening on it has to run as that account or as a system account.
A TCP listener doesn't start while something else on that side already accepts
connections at its address, including a service listening on every address. The
tunnel reports the address as in use until it's free.
A virtual machine's tunnels can have 64 connections open at once, and a single
tunnel 32 of them. Connections beyond that are closed as they arrive.
The relay forwards bytes and supports half-close. Unix ancillary data such as file
descriptors stays local to each operating system.

VirtualBuddyGuest → Service Tunnels → Request Service Tunnel sends a proposal to the host's
Service Tunnels settings. Allow saves the reviewed tunnel list in
`.vbdata/ServiceTunnels.plist` and records its approval on this Mac. An approval belongs to
that virtual machine on this Mac and user account. Duplicating the virtual machine in the
VirtualBuddy library approves the same tunnels for the copy. A bundle copied in Finder,
moved to another volume, restored from a backup or brought over from another Mac needs its
tunnels reviewed again: open Service Tunnels and choose **Approve Tunnels**. Pending
proposals expire when the guest session ends. Turning off or removing an approved mapping
closes its active connections. Enabled mappings start again when a compatible guest reconnects.

The host shows why a tunnel isn't working on either side. The guest is only told that a
tunnel isn't available on the host, not the reason, which would describe the host's files
and services. Status text received from the other side is stripped of characters that
could disguise it before it's displayed.

An organization can turn service tunnels off, or restrict their direction, the kinds of
endpoints they use and the host ports and socket paths they can reach, with a
configuration profile. See [Managed preferences](ManagedPreferences.md#restrict-service-tunnels).
The policy is applied on the host on top of what the user approved.

The session negotiates `service-tunnels.v1`. VirtualWormhole carries the rule list,
proposals, and rendezvous messages. Each accepted client gets a dedicated Virtio
stream identified by a per-connection nonce. Both directions use the selected VM's
socket device and a guest listener that accepts the host context ID.

VirtualCore's `ApprovedVMSetting<Value>` supports other sensitive bundle settings.
Give each feature a stable identifier, a schema version, and a validator for values
that are safe to display and apply. Use `approvedValue(in:)` on runtime paths to check
the approval before decoding the setting. Use `reviewValue` to display a candidate for
explicit host approval. Saving other VM settings must preserve the record without approving it.

The record in the bundle is only a candidate: anything that can write to the bundle can
change it. The approval is a SHA-256 digest kept in the host's Keychain as a
non-synchronizing, device-only data protection item available after first unlock. The
digest covers the feature identifier, schema version, format domain, the virtual
machine's identifier and the exact encoded payload, and it is stored under the volume
and file identifier of the bundle directory. Only the record matching that digest is
approved, so a record that was replaced can't be put back, and a record or a whole
bundle copied elsewhere isn't approved in its new place. Renaming a bundle or moving it
within its volume keeps the approval. The library's Duplicate command reads the
original's approved value and approves it for the copy. Any new setting of this kind
has to be added to `VBVirtualMachine.carryApprovedSettings(from:to:)` to get the same
treatment. These settings are unavailable for a bundle on a volume without a persistent
identifier.

The VirtualBuddy scheme runs the Keychain integration test inside the signed host
app. The VirtualCore suite covers duplication, copies made outside the library,
replaced records, tampering, and approval by independent hosts.
