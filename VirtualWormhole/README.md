# VirtualWormhole

This is the communication API between VirtualBuddy running on the macOS host, and VirtualBuddyGuest running inside the VM.

VirtualBuddy establishes a connection with its guests by using a `VZVirtioSocketDevice`.

Communications use WebSocket via SwiftNIO where the guest is the server, and VirtualBuddy is the client.

VirtualBuddy running on the host gets a file descriptor via `VZVirtioSocketConnection` then uses SwiftNIO to establish a WebSocket connection with it.

To allow for faster iteration during development, `WHGuestClient` can send this file descriptor to another process via XPC, that process then handles all
protocol communications for that socket connection. The `WHRemoteClient` target implements the XPC service, so during development of new services that communicate
over VirtualWormhole, it's possible to build and run `WHRemoteClient` instead of having to constantly shut down VMs and rebuild VirtualBuddy itself.
