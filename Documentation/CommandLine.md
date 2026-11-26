# Command-Line Tool

`vbctl` controls VirtualBuddy and its virtual machines from Terminal and from scripts. It can start and stop virtual machines, change the settings of running ones, and use features of the [VirtualBuddyGuest app](../README.md#virtualbuddyguest-app) such as dark mode and [service tunnels](ServiceTunnels.md).

## Turn it on

Command-line access is off until you turn it on.

1. Open **VirtualBuddy → Settings → Security** and click **Unlock…**.
2. Turn on **Allow vbctl to control VirtualBuddy**.
3. Click **Install Command-Line Tool…** to link `vbctl` into a folder in your `PATH`.

VirtualBuddy only installs into folders you can already write to, such as `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` or `~/bin`, and only when they're in the `PATH` your shell sets up. If there's no such folder, it gives you a `sudo ln -s` command to run instead. You can also run the tool without installing it, from inside the app:

```sh
/Applications/VirtualBuddy.app/Contents/MacOS/vbctl --help
```

The installed link follows the app when you move it: VirtualBuddy points the link at its new location the next time it opens.

For tab completion, add the script that `vbctl --generate-completion-script zsh` prints to your shell's completions. `bash` and `fish` are supported the same way.

## Use it

A virtual machine is referred to by its name, its UUID or the path of its bundle. Names aren't case-sensitive.

```sh
vbctl list                              # every virtual machine and its state
vbctl start Sequoia --wait-for-guest    # start, and wait for VirtualBuddyGuest to connect
vbctl guest appearance Sequoia dark     # switch the guest to dark mode
vbctl tunnel add Sequoia host:8080 guest:3000
vbctl display Sequoia --size 2560x1440
vbctl stop Sequoia --wait
```

VirtualBuddy is opened in the background when it isn't running. Pass `--no-launch` to fail instead.

| Command | What it does |
| --- | --- |
| `list` (`ls`) `[--running]` | Lists the virtual machines in the library. |
| `status [<vm>]` | Shows the app's status, or the details of one virtual machine. |
| `library` | Opens the library window. |
| `open <vm>` | Opens a virtual machine's window without starting it. |
| `start` (`boot`) `<vm>` | Starts a virtual machine, continuing from its saved state if it has one and resuming it if it's paused. `--recovery`, `--dfu` and `--install-device` choose how it starts. `--discard-saved-state` deletes the saved state first. `--wait-for-guest` waits for VirtualBuddyGuest. |
| `stop <vm> [--wait] [--force]` | Asks the guest to shut down. `--force` stops it immediately, which can lose data. |
| `pause <vm>`, `resume <vm>` | Pauses or resumes a virtual machine. |
| `save <vm>` | Saves the virtual machine's state and stops it. |
| `guest status <vm> [--wait]` | Shows whether VirtualBuddyGuest is connected. |
| `guest info <vm>` | Shows what the guest last reported about its system. |
| `guest appearance <vm> [dark\|light\|toggle\|auto]` | Shows or changes the guest's appearance. `auto` follows your Mac. |
| `tunnel list <vm>` | Lists service tunnels, and the ones waiting for review. |
| `tunnel add <vm> <listen> <destination> [--wait]` | Adds a service tunnel. |
| `tunnel enable\|disable\|remove <vm> <tunnel>` | Changes a tunnel, named by the end it listens on (`host:8080`) or the start of its ID. |
| `tunnel decline <vm> <tunnel>` | Declines a tunnel that's waiting for review. |
| `display <vm> [--size <w>x<h>] [--ppi <n>] [--auto-resize on\|off]` | Shows or changes the display. |
| `share list\|add\|remove <vm> [<path>] [--read-only]` | Manages shared folders. |
| `network status\|reconnect <vm>`, `network bridge <vm> <interface>` | Manages the network. |
| `usb list <vm>`, `usb attach\|detach <vm> <device>` | Attaches USB devices connected to your Mac. Requires macOS 27. |

Changing the display, shared folders, network and USB devices applies to a running virtual machine. `vbctl help <command>` describes each command in full.

### Service tunnels

An end of a tunnel is written as the side it's on, followed by a TCP port or the path of a Unix socket. The first end is where the tunnel listens, and the second is the service it connects to.

```sh
vbctl tunnel add Sequoia host:8080 guest:3000        # open the guest's port 3000 at localhost:8080 on your Mac
vbctl tunnel add Sequoia guest:5432 host:5432        # let the guest reach a database on your Mac
vbctl tunnel add Sequoia host:tcp6:8080 guest:tcp6:3000
vbctl tunnel add Sequoia guest:/tmp/agent.sock host:/Users/me/.agent.sock
```

`vbctl` never approves a tunnel. What happens to a tunnel it adds depends on **Settings → Security → Tunnel review**, the same as for a tunnel a virtual machine requests:

- If the tunnel doesn't have to be reviewed, it's added right away.
- If it does, and VirtualBuddyGuest is connected, the tunnel waits in VirtualBuddy for you to review it. `vbctl` exits with code 8, or waits for your decision with `--wait`.
- If it does, and there's nowhere for it to wait, nothing is changed and `vbctl` exits with code 8. Add the tunnel in the virtual machine's settings instead.

Turning a tunnel off and removing it never need a review. Turning one on follows the review level.

### Scripts

Add `--json` to any command for output that's meant to be parsed, `--quiet` to leave out progress and confirmations, and `--timeout <seconds>` to limit how long a command waits. Errors go to standard error, as JSON with a `code` and a `message` when `--json` is used.

| Exit code | Meaning |
| --- | --- |
| 0 | Success. |
| 1 | The command failed. |
| 3 | Command-line access is off, or VirtualBuddy couldn't be reached. |
| 4 | Nothing matches the name, or more than one thing does. |
| 5 | The virtual machine is in the wrong state for the command. |
| 6 | VirtualBuddyGuest isn't connected, or the feature isn't supported. |
| 7 | Timed out. |
| 8 | A review is needed in VirtualBuddy, or your organization doesn't allow it. |
| 64 | The command was written incorrectly. |

Commands never wait for a decision in the app. A start that would normally ask something, such as what to do with a saved state that the chosen boot options can't continue from, fails with an explanation of what to pass or where to decide.

## Security

`vbctl` is VirtualBuddy's own executable under another name, and talks to the app over a Unix socket in a folder only your account can open. The socket exists only while command-line access is on. For every connection, the app checks the code signature of the process on the other end and only answers its own executable, and `vbctl` checks the app the same way.

That check establishes what's talking to the app, not what started it. While command-line access is on, anything running as you can run `vbctl`. For that reason:

- The setting is off by default, and changing it requires Touch ID or your account password.
- `vbctl` can't change security settings, approve deep link clients, or approve service tunnels.
- Service tunnels it adds are reviewed at the level you chose.

On a managed Mac, your organization can [disable command-line access](ManagedPreferences.md#disable-command-line-access).
