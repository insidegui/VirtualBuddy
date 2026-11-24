# Mac debugging packages

VirtualBuddy uses three local Swift packages for Xcode deployment and debugging on Apple silicon Macs running macOS 14 or later. Another app can add the host or target package as a local package dependency. Keep the three directories together so SwiftPM can resolve their shared dependency.

| Package | Responsibility |
| --- | --- |
| [MacDebugHost](MacDebugHost/Package.swift) | Xcode scheme discovery and generation, build pre-action, LLDB module, run broker, and system symbol cache |
| [MacDebugTarget](MacDebugTarget/Package.swift) | System image discovery, signed debug app validation and installation, and the lifetime of Apple's `debugserver` |
| [MacDebugProtocol](MacDebugProtocol/Package.swift) | Launch options, image manifest, host-side `RemoteDebugSession` contract, and duplex socket I/O |

### Host integration

Create a `DebugHostConfiguration` with the app URL, helper executable, and a short, private per-user socket directory. The generated scheme loads the LLDB module from the package's resource bundle. Forward the helper's arguments to `DebugHostCommand.run`. Create one `DebugSymbolCache` with the app's chosen cache directory and helper, and share it between the broker and cache management UI.

Start a `DebugBroker` with an authorization check and a closure that resolves a stable destination UUID to a `RemoteDebugSession`. Use `DebugScheme.choices(in:)` and `install(destination:named:configuration:)` to create the user's Xcode scheme. Stop the broker when the app shuts down.

### Target integration

After authorizing the controller, reserve the destination for one active run and create a `TargetDebugRun` for its run ID. Return its image manifest. Supply requested files through `imageURL(named:)` and receive the complete app archive at `archiveURL` before calling `install()`. That returns the installed bundle URL for LLDB's path mapping. Pass the connected debugger stream and launch options to `serve(over:options:)`. On disconnect, cancel the run and its transfers. Retain the run until outstanding file operations finish.

VirtualBuddy implements this contract using VMBridge requests and file transfers plus a dedicated Virtio socket. The app owns VM startup, login readiness, managed preferences, and verification that the debugger connection came from the host. The guest uses its installed Apple Command Line Tools or Xcode.

A peer-to-peer app can adopt both roles. Its adapter resolves a paired Mac's UUID, carries the control messages and files, and supplies an ordered, reliable byte stream for each debug session. For a transport that delivers messages, bridge an authenticated peer channel to one end of a local socket pair and pass the other end to the package as a `DebugSocket`. Forward bytes in both directions and close the socket when the peer disconnects.

Each package's tests run with `swift test` in its directory.
