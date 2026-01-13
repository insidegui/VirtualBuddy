# VirtualBuddy Linux Guest Additions

This package provides automatic filesystem resizing for Linux virtual machines running in VirtualBuddy.

When you resize a disk in VirtualBuddy, the guest additions will automatically expand the partition and filesystem on the next boot.

## Features

- **Automatic partition resize** using `growpart`
- **LVM support** - automatically extends physical volumes and logical volumes
- **LUKS support** - automatically resizes encrypted containers
- **LVM on LUKS** - full support for Fedora Workstation's default layout
- **Multiple filesystems** - supports ext4, XFS, and Btrfs
- **Safe operation** - only runs when free space is detected
- **Desktop notifications** - shows a notification when disk is resized (desktop environments)
- **Colorful terminal output** - easy to follow installation and resize progress

## Supported Distributions

Any systemd-based Linux distribution, including:

- Fedora Workstation / Server
- Ubuntu
- Debian
- Arch Linux
- openSUSE
- Rocky Linux / AlmaLinux

## Installation

### Quick Install (from inside the VM)

```bash
# Download and extract
curl -L https://github.com/insidegui/VirtualBuddy/releases/latest/download/LinuxGuestAdditions.tar.gz | tar xz

# Install
cd LinuxGuestAdditions
sudo ./install.sh
```

### Manual Install

1. Copy the files to your VM
2. Run the installer:

```bash
sudo ./install.sh
```

The installer will:
- Check for required dependencies (`growpart`, `resize2fs`/`xfs_growfs`)
- Install the `virtualbuddy-growfs` script to `/usr/local/bin/`
- Install the `virtualbuddy-notify` script for desktop notifications
- Install and enable the systemd services
- Optionally run the resize immediately

## Desktop Notifications

On desktop distributions (GNOME, KDE, Xfce, etc.), the guest additions will show a notification when the disk has been resized:

- **Installation notification** - Shown when you run the installer
- **Resize notification** - Shown after login if the disk was resized during boot

The notification shows:
- Previous disk size
- New disk size

This makes it easy to confirm that your disk expansion worked, even though the resize happens early in the boot process.

**Requirements for notifications:**
- X11 or Wayland display server
- `notify-send` command (usually provided by `libnotify`)

## Dependencies

The following packages are required:

| Distribution | Package |
|-------------|---------|
| Fedora/RHEL | `cloud-utils-growpart` |
| Ubuntu/Debian | `cloud-guest-utils` |
| Arch Linux | `cloud-guest-utils` (AUR) |
| openSUSE | `growpart` |

Install with:

```bash
# Fedora
sudo dnf install cloud-utils-growpart

# Ubuntu/Debian
sudo apt install cloud-guest-utils

# Arch (from AUR)
yay -S cloud-guest-utils
```

## Usage

### Automatic (Recommended)

After installation, the service runs automatically on each boot. If VirtualBuddy has expanded the disk, the partition and filesystem will be resized.

### Manual

You can also run the resize manually:

```bash
# Run with verbose output
sudo virtualbuddy-growfs --verbose

# Dry run (show what would happen)
sudo virtualbuddy-growfs --dry-run --verbose
```

### Check Status

```bash
# Service status
systemctl status virtualbuddy-growfs

# View logs
journalctl -u virtualbuddy-growfs
```

## How It Works

1. **Detect storage stack** - Walks from root filesystem back through LVM, LUKS, to the partition
2. **Find free space** - Checks if partition can be grown
3. **Grow partition** - Uses `growpart` to extend the GPT partition
4. **Resize LUKS** - If encrypted, runs `cryptsetup resize`
5. **Resize LVM** - If using LVM:
   - `pvresize` to extend the physical volume
   - `lvextend` to extend the logical volume
6. **Resize filesystem** - Runs the appropriate tool:
   - ext4: `resize2fs`
   - XFS: `xfs_growfs`
   - Btrfs: `btrfs filesystem resize max`

## LVM Support

For distributions using LVM (with or without encryption), the guest additions automatically handle:

1. Extending the physical volume (`pvresize`)
2. Extending the logical volume (`lvextend -l +100%FREE`)
3. Resizing the filesystem

This works for both:
- **LVM on partition** - direct partition → LVM → filesystem
- **LVM on LUKS** - partition → LUKS → LVM → filesystem (Fedora Workstation default)

## LUKS Encrypted Disks

For LUKS-encrypted root partitions (common with Fedora Workstation), the guest additions will:

1. Grow the GPT partition containing LUKS
2. Run `cryptsetup resize` to expand the LUKS container
3. If LVM is on top of LUKS, extend PV and LV
4. Resize the inner filesystem

No manual intervention required!

## Uninstall

```bash
sudo ./uninstall.sh
```

Or manually:

```bash
# Disable services
sudo systemctl disable --now virtualbuddy-growfs.service
sudo systemctl --global disable virtualbuddy-notify.service

# Remove files
sudo rm /etc/systemd/system/virtualbuddy-growfs.service
sudo rm /etc/systemd/user/virtualbuddy-notify.service
sudo rm /usr/local/bin/virtualbuddy-growfs
sudo rm /usr/local/bin/virtualbuddy-notify
sudo rm -rf /etc/virtualbuddy

# Reload systemd
sudo systemctl daemon-reload
```

## Troubleshooting

### "growpart not found"

Install the cloud-utils package for your distribution (see Dependencies section).

### Partition not growing

Check if there's actually free space after the partition:

```bash
sudo parted /dev/vda print free
```

If the "Free Space" at the end is very small (< 1MB), VirtualBuddy may not have resized the disk yet.

### LUKS resize fails

Ensure the LUKS container is unlocked (you should be booted into the system). The resize requires the container to be open.

### Filesystem resize fails

Check the filesystem type and ensure the appropriate tools are installed:

```bash
# Check filesystem type
df -T /

# For ext4
sudo apt install e2fsprogs  # or dnf install e2fsprogs

# For XFS
sudo apt install xfsprogs   # or dnf install xfsprogs

# For Btrfs
sudo apt install btrfs-progs  # or dnf install btrfs-progs
```

### LVM not detected

Ensure LVM tools are installed:

```bash
# Fedora/RHEL
sudo dnf install lvm2

# Ubuntu/Debian
sudo apt install lvm2
```

Check your storage stack:

```bash
# View LVM layout
sudo lsblk
sudo lvs
sudo pvs
sudo vgs
```

### LV not extending

If the logical volume isn't growing, check for free space in the volume group:

```bash
sudo vgs
```

If `VFree` is 0, the physical volume may not have been resized. Try running manually:

```bash
sudo pvresize /dev/mapper/luks-xxx  # or your PV device
sudo lvextend -l +100%FREE /dev/mapper/fedora-root
```

## License

MIT License - Same as VirtualBuddy
