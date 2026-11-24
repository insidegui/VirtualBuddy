# Run and debug Mac apps with VirtualBuddy

VirtualBuddy can help you set up an Xcode project so that you can run and debug a Mac app in a virtual machine, similar to how you can build and run an app to an iPhone or iOS Simulator.

## Requirements

On the first launch with this feature, VirtualBuddy turns on developer features if Xcode is installed. You can change this under **VirtualBuddy Settings → Developer → Enable Developer Features**.

The guest needs the current VirtualBuddyGuest app running in a logged-in desktop session and Apple’s Command Line Tools or Xcode installed. Build a signed arm64 macOS app with the Debug configuration and the `com.apple.security.get-task-allow` entitlement, which is added by default in debug builds with Xcode.

## Set up the Xcode scheme

In the VirtualBuddy library, right-click a macOS virtual machine and choose **Set Up Xcode Debugging…**. In the setup sheet, choose the app’s project or workspace and its app scheme. Enable **Custom LLDB Commands** if needed, then click **Create Scheme**. If you enabled the setting, relaunch Xcode. Choose the generated **App — VM** scheme with **My Mac** as the destination, then press **⌘R**.

## Provisioning and device registration

Apps with restricted entitlements, such as a provisioned app group, need a development profile that includes the VM. VirtualBuddy checks the app and its extensions at Run time. With automatic signing, it refreshes profiles when needed using the Xcode selected with `xcode-select` and the account signed in to Xcode. This can be a different installation from the one that ran the scheme.

Register each VM once per signing team. If registration is needed, the provisioning window shows the guest’s **Provisioning UDID**, a copy button, and a link to Apple Developer. After registering the virtual machine, click **Refresh Profiles** to continue the same Run. For manual signing, choose **Import Profiles…** and select the Apple-issued development profiles for the app and its extensions.

For one-click registration, choose **Add Team API Key…** in the provisioning window or in **VirtualBuddy Settings → Developer**. Select the downloaded `.p8` file and enter the App Store Connect issuer ID. VirtualBuddy fills in the key ID from the filename and, when opened from a Run, the signing team ID from the app. Use a **team** key with device registration permission. The key is stored in the host Mac’s Keychain and VirtualBuddy asks for Touch ID or your password before using it, so the provisioning window shows **Check Registration** first. VirtualBuddy asks before registering a virtual machine because registration uses one of the team’s Mac device slots for the membership year. [Apple’s API key permissions](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) · [Apple’s device limits](https://developer.apple.com/help/account/devices/devices-overview/)

## Debugging symbols and performance gauges

The first run can take a while because it copies and extracts symbols for the guest’s macOS build. Manage disk usage in **VirtualBuddy Settings → Developer → Xcode Debugging Symbols**. Deployment and debugging use the VirtualBuddyGuest connection. The custom Xcode launch style is experimental and has been tested with Xcode 27.3 and macOS 27 guests.

Xcode’s Debug navigator uses the selected **My Mac** destination for its performance gauges. Those gauges can show zero or host-side readings during a VM run. Use Activity Monitor inside the VM to inspect the guest process.
