# VirtualBuddy

VirtualBuddy can virtualize macOS 12 and later on Apple Silicon, with the goal of offering features that are useful to developers who need to test their apps on multiple versions of macOS, especially betas.

**Requires macOS 12.3 and an Apple Silicon Mac**

![](./Screenshot.png)

### Feature Checklist

- [x] Ability to boot any version of macOS 12 or macOS 13, including betas
- [x] Built-in installation wizard
	- [x] Select from a collection of restore images available on Apple's servers
	- [x] Install the latest stable version of macOS
	- [x] Local restore image IPSW file
	- [x] Custom restore image URL
- [x] Boot into recovery mode (in order to disable SIP, for example)
- [x] Networking and file sharing support
- [x] Clipboard sharing (without the need to be running macOS Ventura) (experimental ¹)
- [ ] Edit NVRAM variables

_¹ To enable clipboard sharing, build the `VirtualBuddyGuest` scheme, then copy the `VirtualBuddyGuest` app to the virtual machine (through file sharing, for example) and run it. This will keep the clipboard in sync between the guest and host machines. The feature is experimental, so it might be buggy and it's definitely not secure._

## Building and using locally

VirtualBuddy is in early development, therefore pre-built binaries are not officially available yet.

- Edit `Main.xcconfig` and set the `VB_BUNDLE_ID_PREFIX` variable to something unique like `com.yourname.`, then select a team under Signing & Capabilities.
	- You may optionally run with the "Sign to run locally" option to skip this step
- Build the `VirtualBuddy` scheme

## Using the `PrivateEntitlements` scheme

There's a scheme called `VirtualBuddy-PrivateEntitlements` that builds the app with the `com.apple.private.virtualization`, which can be used to explore hidden features of the Virtualization framework that are not normally available.

In order to use this scheme, the Mac must have SIP disabled and `amfi_get_out_of_my_way=1` in boot-args. Do this at your own risk.