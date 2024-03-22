# Wormhole Remote Client

This app is a tool used for development of the VirtualWormhole APIs, which are used by VirtualBuddy to communicate with VirtualBuddyGuest running inside a VM.

It implements the client-side of the connection used by VirtualBuddy on the host and exposes an XPC service that VirtualBuddy talks to in order
to establish connections with guests.

This allows for faster iteration on the VirtualBuddy guest communication protocols because it is a separate target from the main VirtualBuddy app, so
it can be built and run from Xcode without the need to shut down VMs and restart the app completely. Connections will be dropped during this process, but can be
re-established once the WHRemoteClient app is running again. 

