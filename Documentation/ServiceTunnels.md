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

## Choose how much is reviewed

By default, VirtualBuddy asks you about every tunnel a guest requests, and about saved tunnels that weren't approved for that virtual machine on this Mac. If that's more review than you need, you can change it in **Settings → Security → Tunnel review**. Click **Unlock…** first and confirm with Touch ID or your account password.

| Setting | What VirtualBuddy asks about |
| --- | --- |
| **Every Change** | Every tunnel a guest requests, and every saved tunnel that wasn't approved for that virtual machine on this Mac. |
| **New Tunnels Only** | A tunnel the first time it uses a given port or socket on your Mac. Once you've approved a tunnel, any virtual machine can get a tunnel in the same direction to the same host port or socket without asking, whatever it connects on the guest's side. This includes requests from guests and virtual machines copied in Finder. |
| **Never** | Nothing. Guests add tunnels to any port or socket on your Mac on their own, and tunnels saved with a virtual machine run as they are. |

Reviewing less gives software in your virtual machines more reach into your Mac. With **New Tunnels Only**, approving a tunnel for one virtual machine approves the same host port or socket for all of them. With **Never**, anything running in a guest can open a tunnel to any service on your Mac. Only choose it if you trust everything that runs in every one of your virtual machines.

You can go back at any time, and changes apply to running virtual machines right away:

- Tunnels that were added or changed while the setting was **Never** have to be reviewed once you choose more review.
- **Forget Reviewed Tunnels…** clears the list that **New Tunnels Only** relies on. Tunnels that were running because of it stop until you review them. Tunnels you approved in a virtual machine's own settings keep running.

Organization restrictions apply whatever you choose here, and an organization can also set the least review that can be chosen.
