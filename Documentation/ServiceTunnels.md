# Service Tunnels

In the host's VM Settings → Service Tunnels, add a listener and a destination. For example,
listen on Host Mac at `127.0.0.1:8080` and connect to Guest VM at `127.0.0.1:3000`.
A browser on the host can then reach the guest service while the VM's network adapter
is disconnected. Both endpoints support IPv4 loopback, IPv6 loopback, and Unix
stream sockets. A Unix listener requires an unused path in a directory owned by
the current account with group and other write access disabled. The relay forwards
bytes and supports half-close. Unix ancillary data such as file descriptors stays
local to each operating system.

VirtualBuddyGuest → Service Tunnels → Request Service Tunnel sends a proposal to the host's
Service Tunnels settings. Allow signs the reviewed tunnel list and saves it in
`.vbdata/ServiceTunnels.signed.plist`. A library duplicate carries its approval on the
same Mac and user account. On another Mac, review the list in Service Tunnels and choose
**Approve Tunnels**. Pending proposals expire when the guest session ends. Turning off or removing an approved mapping closes its
active connections. Enabled mappings start again when a compatible guest reconnects.

The session negotiates `service-tunnels.v1`. VirtualWormhole carries the rule list,
proposals, and rendezvous messages. Each accepted client gets a dedicated Virtio
stream identified by a per-connection nonce. Both directions use the selected VM's
socket device and a guest listener that accepts the host context ID.

VirtualCore's `SignedVMSetting<Value>` supports other sensitive bundle settings.
Give each feature a stable identifier, a schema version, and a validator for values
that are safe to display and apply. Use `approvedValue(in:)` on runtime paths to verify the signature before decoding the setting.
Use `reviewValue` to display a candidate for explicit host approval. Saving other
VM settings must preserve the record without signing it.

The P-256 signature covers the feature identifier, schema version, format domain,
and exact encoded payload. Verification uses the local signing identity. Its private
key is a non-synchronizing, device-only data protection Keychain item available
after first unlock. Approvals apply to the signed values across VM bundles in that
account, including restored copies of previously approved configurations.

The VirtualBuddy scheme runs the Keychain integration test inside the signed host
app. The VirtualCore suite covers duplication, tampering, and re-approval with
independent host identities.
