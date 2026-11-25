# Service Tunnels — Threat Model and Security Audit

**Scope:** commits `eb288c7` → `da3024a` on `custom-tunnels` (tunnel protocol, sockets, signed settings, host and guest UI).
**Method:** manual source review of every changed file plus the pre-existing code it relies on (`DebugSocket`, `GuestService`, `GuestSessionEngine`). Two behaviours were confirmed by running small experiments on this Mac (marked *verified by test*); everything else is traced from the code and was not exercised against a running VM.

## Summary

The core enforcement is sound: the host only ever opens listeners or outbound connections for rules whose signature verifies, everything binds to loopback, failures fail closed, and revocation tears down live connections. I found no way for a guest to reach a host endpoint that was never approved.

The weaknesses are concentrated in two places:

1. **The approval moment.** The host user is the only gate, and the UI that gate relies on can show a truncated or misleading endpoint, can have its contents swapped by the guest just before the click, and does not distinguish "expose a guest service" from "hand the guest a host service".
2. **What an approval is bound to.** A signature covers the rule list only, not the VM or a point in time, so an approval can be replayed into another bundle or rolled back to an earlier list.

| ID | Severity | Finding |
|----|----------|---------|
| F1 | Medium | Guest can swap a pending request's contents under the Allow button |
| F2 | Medium | Approval rows truncate endpoints and accept non-canonical, look-alike paths |
| F3 | Medium | Host listeners can silently shadow an existing host service (`SO_REUSEADDR`) or squat a well-known socket path |
| F4 | Medium | Signed approvals are replayable across VMs and can be rolled back |
| F5 | Low | Guest-controlled strings reach the host settings UI unsanitised and unbounded |
| F6 | Low | Unix listener directory check covers only the immediate parent and follows symlinks |
| F7 | Low | Host Unix destinations follow symlinks and do not check who owns the service |
| F8 | Low | One shared 32-connection budget; any local host user can exhaust it through a TCP listener |
| F9 | Low | Proposals cannot be turned off, rate-limited, or remembered as declined |
| F10 | Info | Guest receives every rule and host-side error text, including host paths |
| F11 | Hardening | Signing key is an exportable raw key in the Keychain |

---

## 1. Threat model

### Assets

| Asset | Why it matters |
|-------|----------------|
| Host loopback services and Unix sockets | Many trust any local caller: Docker socket, ssh-agent, gpg-agent, unauthenticated dev databases. Reaching one can equal full host compromise. |
| Host filesystem | The host creates directories and socket files at rule-specified paths. |
| The approval decision | The only control between a guest and the above. |
| Guest services exposed on the host | Reachable by other host processes once tunnelled. |
| Host process resources | File descriptors, blocked threads, main-actor time. |
| Signing key and signed records | Forging or reusing them bypasses the approval decision. |

### Actors

| Actor | Capabilities | Trusted? |
|-------|--------------|----------|
| Host user | Approves rules in VirtualBuddy | Yes |
| Guest (whole VM) | Speaks the full control protocol, opens arbitrary vsock ports, controls all proposal contents and timing. Any process in the guest should be assumed able to do this, not only VirtualBuddyGuest. | **No** |
| Other local users on the host | Can connect to host loopback TCP ports; can create files in shared directories such as `/tmp` | No |
| Other processes of the host user | Same UID; can already reach the user's sockets | Out of scope (cannot be defended against at this layer) |
| Bundle author / writer | Supplies or modifies `.vbdata` without Keychain access: a downloaded VM, a synced or external-drive library, a backup restore | No |

### Trust boundaries and data flows

```
        HOST (trusted)                         │        GUEST (untrusted)
                                               │
 Settings UI ──approve──► SignedVMSetting      │
      ▲                    (.vbdata, P-256)    │
      │ requests, status        │ approvedValue│
      │                         ▼              │
 TunnelGuestService (host) ◄══ control channel (vsock 51780) ══► TunnelGuestService (guest)
      │   ready / snapshot / propose / open / reverse / status  │
      │                                        │                 │
 TunnelListener ──► per-connection vsock stream + nonce ◄── guest listener
 (TCP lo / Unix)                               │            (TCP lo / Unix)
      │                                        │
 Host destination (TCP lo / Unix)              │
```

Boundaries crossed:

- **B1 — control channel.** Every `TunnelControl` and `TunnelReply` from the guest is attacker-controlled.
- **B2 — data streams.** Bytes relayed to a host destination are attacker-controlled; the destination sees them as coming from a local process running as the host user.
- **B3 — approval UI.** Guest-supplied data is rendered inside trusted host UI and becomes a signed rule on one click.
- **B4 — VM bundle.** `ServiceTunnels.signed.plist` lives in a directory an untrusted party may have written.
- **B5 — host filesystem and loopback.** Shared with other local users.

### Inherent properties worth stating in the docs

These are consequences of the feature, not defects, but users deciding whether to approve a rule should know them:

- A tunnel to a host service removes that service's "local callers only" assumption. Peer-credential checks on the service see VirtualBuddy's UID.
- A host TCP listener is reachable by every local user and by anything on the host that can make loopback requests, including web pages in a browser. Only Unix listeners enforce a same-UID check.
- Tunnels work while the VM's network adapter is disconnected, so they are a deliberate hole in network isolation for VMs used to contain untrusted software.

---

## 2. Findings

### F1 — Guest can swap a pending request's contents under the Allow button · Medium

**Where:** [ServiceTunnelsConfigurationView.swift:154-168](VirtualUI/Source/VM%20Configuration/Sections/Tunnels/ServiceTunnelsConfigurationView.swift), [TunnelGuestService.swift:119-124](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift), [TunnelGuestService.swift:267-275](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift)

Allow calls `apply(tunnels + [request])` immediately, using whatever `request` the row holds at click time. The pending list is live guest state: re-initialising the session clears `state.requests`, after which the guest can propose again, reusing the same UUID with different endpoints. The row keeps its identity and position and simply shows new content.

**Scenario:** the guest proposes `Guest 127.0.0.1:8080 → Host 127.0.0.1:3000`, then repeatedly reconnects and alternates it with a rule exposing a host Unix socket. If the click lands while the second rule is displayed, that rule is signed. The guest cannot see the host cursor, so this is probabilistic, but it costs the guest nothing to keep trying and there is no second step to catch it.

**Fix:**
- Make Allow open a confirmation sheet that captures the rule by value, shows both endpoints in full, and signs exactly that captured value.
- On the host, refuse a proposal whose UUID was already seen in this VM run (keep the seen set across session re-initialisation), and keep declined or cleared requests from reappearing in the same row position without a visible change.

### F2 — Approval rows truncate endpoints and accept non-canonical, look-alike paths · Medium

**Where:** [ServiceTunnelListItem.swift:21-40](VirtualUI/Source/VM%20Configuration/Sections/Tunnels/ServiceTunnelListItem.swift), [ServiceTunnel.swift:16-24](VirtualWormhole/Source/Services/Tunnels/ServiceTunnel.swift)

Three gaps combine:

- Rows use `lineLimit(1)` with middle truncation. Two paths of up to 103 bytes cannot fit, so the part of the path that identifies the socket is what gets elided. The full text is only in a tooltip.
- `isValid` accepts `..`, `.` and repeated slashes, so `/Users/me/Public/../Library/…/agent.sock` is a valid rule that does not look like what it resolves to.
- The character filter rejects control and bidi characters but lets through U+2028/U+2029 (line and paragraph separators), no-break space, and homoglyphs such as Cyrillic `а` or U+2215 `∕` (*verified by test* against the exact predicate). Separators interact badly with a one-line label; homoglyphs make a path read as a different one.

The same row is used for the one-click **Approve Tunnels** on an imported bundle, where up to 32 unreviewed rules are signed together.

**Fix:**
- Require canonical paths: reject `.`/`..` components and empty components, and restrict to printable characters with no Unicode separators (`Zl`, `Zp`, and non-ASCII `Zs`). Consider flagging non-ASCII paths in the review UI rather than rejecting them.
- In any approval context, show endpoints untruncated (wrapping, monospaced).
- For an imported bundle, require per-rule approval or at least a confirmation that lists every rule in full.

### F3 — Host listeners can shadow an existing service or squat a well-known path · Medium

**Where:** [TunnelSocket.swift:121-124](VirtualWormhole/Source/Services/Tunnels/TunnelSocket.swift), [TunnelSocket.swift:86-89](VirtualWormhole/Source/Services/Tunnels/TunnelSocket.swift)

A rule that listens on the host looks like the harmless direction ("let my Mac reach a guest service"), but it lets the guest *impersonate* a host service to host clients.

- **TCP:** listeners set `SO_REUSEADDR`. On macOS this lets `127.0.0.1:P` bind while another socket of the same user already listens on `*:P`, and loopback clients are then delivered to the new, more specific socket. *Verified by test* for IPv4 and IPv6 on this machine: with the option the bind succeeds and the client reaches the second listener; without it the bind fails with "Address already in use". Dev servers commonly bind the wildcard address, so an approved rule for their port takes over loopback traffic with no error shown.
- **Unix:** if the real service is not running, a listener can be created at a well-known path (Docker's socket, a password manager's SSH agent socket, gpg-agent). Host tools then talk to the guest, which can collect whatever they send.

Both need an approved rule, which is why this is Medium, but nothing tells the approver that the listener address already belongs to something.

**Fix:**
- Drop `SO_REUSEADDR` from tunnel listeners, or bind without it first and only retry with it after confirming nothing accepts connections on the wildcard address for that port.
- At approval time, probe the host listener address and warn if something is already answering there.
- Phrase host-listener approvals as "apps on this Mac that connect to X will be talking to the virtual machine".

### F4 — Signed approvals are replayable across VMs and can be rolled back · Medium

> **Status: fixed in the working tree.** The signature now covers the VM identifier, and the host keeps a digest of the current approval in the Keychain under the bundle directory's volume and file identifier. The library's Duplicate command re-signs the original's approved value for the copy. The description below is of the code as audited.

**Where:** [SignedVMSetting.swift:60-65](VirtualCore/Source/Models/Configuration/SignedVMSetting.swift), [SignedVMSetting.swift:74-78](VirtualCore/Source/Models/Configuration/SignedVMSetting.swift)

The signed bytes are a domain string, the feature identifier, the schema and the payload. Nothing ties the signature to a VM or to a moment. The documentation presents cross-bundle portability as intentional so that duplicates keep their approval, but the signature exists to protect against an untrusted bundle writer (boundary B4), and against that actor it allows:

- **Cross-VM replay:** copy the record from a VM that was granted a sensitive host socket into the bundle of a VM that was never granted it. It verifies.
- **Rollback:** keep an old record and restore it after the user removes or disables a rule. It verifies. Revocation is therefore not durable against anyone who can write the bundle, including an ordinary backup restore or file sync conflict.

Rollback is not mentioned in the documentation and I believe it is unintended.

**Fix:** see architecture proposal A. A smaller step that closes replay but not rollback is to add the VM's `uuid` to `signedBytes`; `VMBundleDuplicator` assigns a fresh UUID, so duplicates would then need re-approval, which changes the documented behaviour.

### F5 — Guest-controlled strings reach the host UI unsanitised and unbounded · Low

**Where:** [TunnelGuestService.swift:133-135](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift), [TunnelGuestService.swift:92](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift), [TunnelGuestService.swift:241-242](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift)

`.status` messages are capped at 256 characters but not filtered. `TunnelReply.failure` text, from both the control channel and the per-connection link (frames up to 1 MiB), is not capped at all; it becomes a `TunnelError`, is stored in `state.status`, shown next to the rule in host settings, and echoed back to the guest in every snapshot. The guest can therefore put arbitrary text, including bidi overrides, beside a rule in trusted UI ("Listening", or instructions to the user).

**Fix:** pass every guest-originated string through one function that truncates and strips control, format and separator characters. Better, replace free text on the wire with an enum of states plus an errno, and render the wording on the host.

### F6 — Unix listener directory check is shallow and follows symlinks · Low

**Where:** [TunnelSocket.swift:155-181](VirtualWormhole/Source/Services/Tunnels/TunnelSocket.swift), [DebugSocket.swift:42-54](Packages/MacDebugProtocol/Sources/MacDebugProtocol/DebugSocket.swift)

For an existing parent directory only that one directory is checked for ownership and mode, and the check uses `stat`, which follows symlinks. If any ancestor is writable by another local user, that user can point a path component at a different directory owned by the victim between the check and `bind`, so the socket is created somewhere other than the approved location. The subsequent `chmod(path, 0600)` is also by path and follows symlinks, so it can be steered onto another file of the victim's with the same name. Impact is small and it needs an approved rule under a directory another user controls, hence Low. The newly-created-directory branch is handled carefully and I found no problem there.

**Fix:** require every ancestor up to `/` to be owned by root or the user and not group/other-writable (or sticky), using `lstat` per component, and resolve the directory once so the approved path and the bound path cannot diverge. Replace the path-based `chmod` with a restrictive `umask` around `bind`, or `fchmod` on the socket descriptor before binding.

### F7 — Host Unix destinations follow symlinks and do not check the service owner · Low

**Where:** [TunnelSocket.swift:90-97](VirtualWormhole/Source/Services/Tunnels/TunnelSocket.swift)

An approved host destination is connected to by path at each use, with no check on the directory or on who is listening. If the approved path is in a shared directory such as `/tmp`, another local user can plant their own socket there (receiving the guest's traffic) or a symlink to a socket that only the host user can open, which VirtualBuddy will then connect to on the guest's behalf.

**Fix:** apply the same ancestor check as F6 before connecting, and verify with `getpeereid` that the destination's owner is the user or root. Warn at approval time when a destination sits in a directory others can write to.

### F8 — Shared connection budget is exhaustible from the host side · Low

**Where:** [TunnelGuestService.swift:189-190](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift), [TunnelSocket.swift:34-42](VirtualWormhole/Source/Services/Tunnels/TunnelSocket.swift)

The 32-connection limit is per VM and shared by all rules and both directions. Any local user can open 32 connections to one host TCP listener and hold them, blocking every other tunnel for that VM; there is no idle timeout. Separately, any `accept` error other than three transient ones (notably `EMFILE`) stops the listener for good until the rule is toggled.

**Fix:** budget per rule as well as per VM, add an idle timeout for connections that never carry data, and on `EMFILE`/`ENFILE`/`ENOBUFS` back off and retry instead of stopping.

### F9 — Proposals cannot be disabled, rate-limited or remembered · Low

**Where:** [TunnelGuestService.swift:119-124](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift), [VirtualMachineSessionView.swift:118-126](VirtualUI/Source/Session/VirtualMachineSessionView.swift)

Any guest that advertises the capability can keep up to 32 requests pending, change the toolbar item to "Review Tunnel Requests (N)", and re-propose a rule the moment it is declined. For VMs running untrusted software this is a standing prompt-fatigue channel into F1 and F2.

**Fix:** a per-VM setting to accept proposals (consider off by default for imported bundles), a per-run deny list so a declined listener stays declined, and a cap on proposals per minute.

### F10 — Guest receives all rules and host error text · Info

**Where:** [TunnelGuestService.swift:96-102](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift), [TunnelGuestService.swift:249](VirtualWormhole/Source/Services/Tunnels/TunnelGuestService.swift)

Snapshots send every rule, including host listener paths (which usually contain the host account name) and host-side status strings. Connection failures to a host destination are reported to the guest with the system error text.

**Fix:** send the guest only what it needs to act: for host-listening rules, the rule ID and guest destination; and a coarse status instead of host error descriptions.

### F11 — Signing key is an exportable raw key · Hardening

**Where:** [HostSettingsSigningKey.swift:12-54](VirtualCore/Source/Utilities/HostSettingsSigningKey.swift)

The private key is stored as generic-password data and loaded into process memory for every verification, although verification only needs the public key. Note also that the app's entitlements file declares no keychain access group; the item therefore relies on the default group derived from the code signature, which is worth confirming for every distribution configuration (the scheme's Keychain test covers the signed development build).

**Fix:** use a Secure Enclave P-256 key (`SecureEnclave.P256.Signing.PrivateKey`), which is non-exportable, and persist only its public key for verification. Fall back to the current scheme on hardware without an enclave.

---

## 3. Architecture proposals

### A. Bind approvals to a VM and to host-side state (addresses F4)

Keep the record in the bundle for portability of the *proposal*, but make the *approval* live on the host:

- Include the VM `uuid` in the signed bytes.
- Keep a small host-side store (Keychain item or Application Support file outside any bundle) mapping VM UUID → digest of the currently approved payload. At runtime, a record is honoured only if its signature verifies **and** its digest matches the store.
- Removing or changing rules updates the store, so an older record no longer matches and rollback fails.

Cost: duplicates, restored backups and moved libraries show "Needs Review" once. That is the same experience the feature already has on a second Mac, and it makes revocation mean what users expect.

### B. Treat the two directions as different permissions (addresses F1, F2, F3, F9)

"Host can reach a guest service" and "guest can reach a host service" carry very different risk, but they share one list, one row style and one button. Suggested shape:

- A dedicated approval sheet for every new rule, showing a frozen copy in full.
- Host-service rules get explicit wording about what the guest will be able to do, and a stronger warning for Unix sockets and for paths matching known agent sockets.
- Host-listener rules get the "already in use" probe and impersonation wording from F3.
- A per-VM policy for whether the guest may propose at all.

### C. Typed status on the wire (addresses F5, F10)

Replace free-form strings in `TunnelControl.status` and `TunnelReply.failure` with a small enum plus an optional errno. Each side renders its own text. This removes the guest-to-host text channel entirely and stops host error detail from flowing to the guest.

---

## 4. What held up

Checked and found correct:

- Runtime rules come only from `approvedValue(in:)`, which verifies the signature before decoding; any error yields an empty rule list.
- `.open` and `.reverse` re-check that the rule is currently approved, enabled and of the right direction on every connection.
- All TCP endpoints are loopback-only on both sides; ports are validated; the control port cannot be used as a rendezvous port.
- Unix listeners check the connecting peer's UID, never unlink a pre-existing file, and only remove a socket file whose device and inode match the one they created.
- Path length is checked against `sun_path`, and NUL and control characters are rejected.
- Disabling or removing a rule cancels its in-flight connections; session teardown stops all listeners.
- Signed-settings file access uses `O_NOFOLLOW`, a regular-file check, a size cap, and atomic replacement.
- Rule count, pending requests, concurrent connections, connect and handshake waits are all bounded.

## 5. Suggested order of work

1. F1 and F2 together: confirmation sheet with a frozen, untruncated rule; canonical path validation.
2. F3: remove `SO_REUSEADDR` from listeners; add the in-use probe.
3. F4: decide on proposal A (behaviour change for duplicates) or document rollback as accepted.
4. F5 with proposal C.
5. F6–F9 as hardening.
