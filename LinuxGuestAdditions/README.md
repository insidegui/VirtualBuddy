# VirtualBuddy Linux Guest Additions

This package provides automatic filesystem resizing for Linux virtual machines running in VirtualBuddy.

When you resize a disk in VirtualBuddy, the guest additions will automatically expand the partition and filesystem on the next boot.

## Features

- **Automatic partition resize** using `growpart`
- **LUKS support** - automatically resizes encrypted containers
- **Multiple filesystems** - supports ext4, XFS, and Btrfs
- **Safe operation** - only runs when free space is detected

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
- Install and enable the systemd service
- Optionally run the resize immediately

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

1. **Detect root device** - Finds the root filesystem mount
2. **Check for LUKS** - Detects if root is on an encrypted volume
3. **Find free space** - Checks if partition can be grown
4. **Grow partition** - Uses `growpart` to extend the GPT partition
5. **Resize LUKS** - If encrypted, runs `cryptsetup resize`
6. **Resize filesystem** - Runs the appropriate tool:
   - ext4: `resize2fs`
   - XFS: `xfs_growfs`
   - Btrfs: `btrfs filesystem resize max`

## LUKS Encrypted Disks

For LUKS-encrypted root partitions (common with Fedora Workstation), the guest additions will:

1. Grow the GPT partition containing LUKS
2. Run `cryptsetup resize` to expand the LUKS container
3. Resize the inner filesystem

No manual intervention required!

## Uninstall

```bash
sudo ./uninstall.sh
```

Or manually:

```bash
sudo systemctl disable --now virtualbuddy-growfs.service
sudo rm /etc/systemd/system/virtualbuddy-growfs.service
sudo rm /usr/local/bin/virtualbuddy-growfs
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

## License

MIT License - Same as VirtualBuddy
