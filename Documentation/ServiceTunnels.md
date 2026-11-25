# Service Tunnels

A service tunnel lets an app on your Mac (the host) connect to a local service in a macOS virtual machine (the guest), or the other way around. For example, you can run a development web server in the guest and open the site in Safari on your Mac. This works even when the virtual machine’s network adapter is turned off.

Tunnels work while the [VirtualBuddyGuest app](../README.md#virtualbuddyguest-app) is connected. Enabled tunnels start again automatically when the guest reconnects.

## Open a guest web server on your Mac

Suppose your web server is running at `http://127.0.0.1:3000` inside the guest and port `8080` is free on your Mac.

1. On your Mac, open **VM Settings → Service Tunnels** for that virtual machine and click **Add Service Tunnel**.
2. Set **Service Runs On** to **Guest**. Leave **Socket** set to **TCP · 127.0.0.1** and enter `3000` for the port.
3. Under **Access from Host**, leave the same socket setting and enter `8080` for the port. Click **Add** and save the VM settings.
4. On your Mac, open `http://127.0.0.1:8080` in Safari. You’ll see the site served by the guest.

To reach a service running on your Mac from inside the guest, choose **Host** under **Service Runs On**. Enter the port your service uses on the Mac, then choose a free port under **Access from Guest**. For services that use IPv6 or a Unix socket, choose the matching option in the **Socket** menu.

## Manage access

You can turn a tunnel off or remove it in **VM Settings → Service Tunnels**. Either action closes its active connections.

You can also request a tunnel from inside the guest. In **VirtualBuddyGuest → Service Tunnels**, choose **Request Service Tunnel**. On your Mac, open the VM’s **Service Tunnels** settings and click **Allow…** to review which service will be reachable and from where. Click **Allow** to approve the request.

If you copy a VM in Finder or bring it over from another Mac, review its saved tunnels and choose **Approve Tunnels** to use them. On a managed Mac, your organization can [restrict service tunnels](ManagedPreferences.md#restrict-service-tunnels).
