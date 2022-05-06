# Virtualize Apple Silicon macOS with powerful developer features

VirtualBuddy can virtualize macOS 12 and later on Apple Silicon with powerful developer features such as the ability to boot into recovery mode, edit NVRAM variables, and more.

![](./VirtualBuddy.png)

## Building and using locally

Project is very much in a "development alpha" stage at the moment.

- Edit `Main.xcconfig` and set the `VB_BUNDLE_ID_PREFIX` variable to something unique like `com.yourname.`, then select a team under Signing & Capabilities.
- VirtualBuddy is currently hardcoded to look for VMs in ~/Documents/VirtualBuddy
- The app doesn't support installation just yet, you can [use Apple's sample code](https://developer.apple.com/documentation/virtualization/running_macos_in_a_virtual_machine_on_apple_silicon_macs) to install a VM and then change its extension to `vbvm` and move into the appropriate directory
- VM bundles must have the `vbvm` extension

## Using the `PrivateEntitlements` scheme

There's a scheme called `VirtualBuddy-PrivateEntitlements` that builds the app with the `com.apple.private.virtualization`, which enables special capabilities such as the ability to boot a "dev-fused" VM. Installing the dev-fused VM must be done with Apple's sample code signed with the same entitlement.

When using this scheme, the Mac must have SIP disabled and `amfi_get_out_of_my_way=1` in boot-args.