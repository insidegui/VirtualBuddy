# Mac debugging packages

VirtualBuddy uses local Swift packages for Xcode deployment and debugging on Apple silicon Macs running macOS 14 or later. Another app can add the host or target package as a local package dependency alongside MacDebugProtocol. App Store Connect device registration is independently adoptable.

| Package | Responsibility |
| --- | --- |
| [MacDebugHost](MacDebugHost/Package.swift) | Xcode scheme discovery and generation, development profile selection, staged signing, LLDB handoff, run broker, and system symbol cache |
| [MacDebugTarget](MacDebugTarget/Package.swift) | System image discovery, signed debug app validation and installation, and the lifetime of Apple's `debugserver` |
| [MacDebugProtocol](MacDebugProtocol/Package.swift) | Launch options, image manifest, host-side `RemoteDebugSession` contract, and duplex socket I/O |
| [AppStoreConnectDevices](AppStoreConnectDevices/Package.swift) | Local Keychain storage of per-team API credentials, Mac lookup and registration |

### Host integration

Create a `DebugHostConfiguration` with the app URL, helper executable, and a short, private per-user socket directory. The generated scheme loads the LLDB module from the package's resource bundle. Forward the helper's arguments to `DebugHostCommand.run`. Create one `DebugSymbolCache` with the app's chosen cache directory and helper, and share it between the broker and cache management UI.

Start a `DebugBroker` with an authorization check and a closure that resolves a stable destination UUID to a `RemoteDebugSession`. Use `DebugScheme.choices(in:)` and `install(destination:named:configuration:bindings:)` to create the user's Xcode scheme. Call `start()` while debugging is enabled and `stopListening()` when the user turns it off, so the socket exists only while it is needed; runs that are already debugging continue. Call `stop()` when the app shuts down.

Give the broker and `install` the same `DebugBindingStore`, such as a `KeychainDebugBindingStore` with an app-specific service name. Creating a scheme records its binding, and the broker starts runs only for recorded bindings, on the destination stored with them. The broker accepts connections only from a process that satisfies the app's own code-signing requirement, so ship the helper as part of the signed app.

The helper extracts system libraries inside a sandbox that can read only the app bundle, the helper, Apple's extractor and the transferred images. Profiles are refreshed with the Xcode selected by `xcode-select`, not the developer directory reported by the Run action.

Pass the broker a `DebugProvisioning` with an app-owned profile cache and a `DebugProvisioningInteraction` for progress, cancellation, registration, and manual profile selection. The broker asks its session for the target’s provisioning UDID only for builds with embedded profiles. The target adapter can answer with `try await MacProvisioningIdentity.current.udid()`. The same interface works for a paired remote Mac.

For App Store Connect registration, initialize `DeviceRegistrationKeys` with an app-specific Keychain service name. Keys are stored in the data protection Keychain behind user presence, so the app must be signed with an application identifier. Keep one `MacDeviceRegistration` value for one user-initiated task: its calls share a single Touch ID or password confirmation. Save one team key per signing team, then use `MacDeviceRegistration(keys:)` to look up that Mac’s exact UDID. Obtain the developer’s approval before calling `register(name:udid:teamID:)` for a missing Mac. A disabled device requires action by the team administrator.

### Target integration

After authorizing the controller, reserve the destination for one active run and create a `TargetDebugRun` for its run ID. Return its image manifest. Supply requested files through `imageURL(named:)` and receive the complete app archive at `archiveURL` before calling `install()`. That returns the installed bundle URL for LLDB's path mapping. Pass the connected debugger stream and launch options to `serve(over:options:)`. On disconnect, cancel the run and its transfers. Retain the run until outstanding file operations finish.

VirtualBuddy implements this contract using VMBridge requests and file transfers plus a dedicated Virtio socket. The app owns VM startup, login readiness, managed preferences, and verification that the debugger connection came from the host. The guest uses its installed Apple Command Line Tools or Xcode.

A peer-to-peer app can adopt both roles. Its adapter resolves a paired Mac's UUID, carries the control messages and files, and supplies an ordered, reliable byte stream for each debug session. For a transport that delivers messages, bridge an authenticated peer channel to one end of a local socket pair and pass the other end to the package as a `DebugSocket`. Forward bytes in both directions and close the socket when the peer disconnects.

Each package's tests run with `swift test` in its directory.
