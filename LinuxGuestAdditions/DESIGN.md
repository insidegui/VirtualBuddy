# Linux Guest Tools - Phase 2 Design

## Overview

This document describes the implementation of auto-mountable Linux guest tools for VirtualBuddy, following the same pattern as VMware Tools, VirtualBox Guest Additions, and Parallels Tools.

## Goals

1. **Zero-copy installation** - User doesn't need to download or transfer files
2. **One-command install** - Single command to install all guest tools
3. **Update detection** - Guest can detect when newer tools are available
4. **Cross-distro support** - Works on Fedora, Ubuntu, Debian, Arch, etc.
5. **Offline operation** - No network required for installation

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        VirtualBuddy Host                         │
├─────────────────────────────────────────────────────────────────┤
│  LinuxGuestAdditionsDiskImage.swift                             │
│  ├── Monitors LinuxGuestAdditions/ directory                    │
│  ├── Generates ISO image on app launch (if needed)              │
│  └── Stores ISO in ~/Library/Application Support/VirtualBuddy/  │
├─────────────────────────────────────────────────────────────────┤
│  LinuxVirtualMachineConfigurationHelper.swift                   │
│  └── Attaches ISO as virtio block device when VM starts         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Linux Guest VM                            │
├─────────────────────────────────────────────────────────────────┤
│  /dev/vdX (VirtualBuddy Tools ISO)                              │
│  └── Mount and run install.sh                                   │
├─────────────────────────────────────────────────────────────────┤
│  Installed Components:                                          │
│  ├── /usr/local/bin/virtualbuddy-growfs                         │
│  ├── /etc/systemd/system/virtualbuddy-growfs.service            │
│  └── /etc/virtualbuddy/version                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Disk Image Format

**ISO 9660 with Joliet extensions** (recommended)
- Universal read support across all Linux distributions
- Read-only by design (prevents accidental modifications)
- Standard pattern used by VMware, VirtualBox, Parallels
- Can be created on macOS using `hdiutil makehybrid`

Volume label: `VBTOOLS`

## ISO Contents

```
VirtualBuddyLinuxTools.iso (VBTOOLS)
├── autorun.sh                      # Quick-start script
├── install.sh                      # Full installer (existing)
├── uninstall.sh                    # Uninstaller (existing)
├── virtualbuddy-growfs             # Main resize script (existing)
├── virtualbuddy-growfs.service     # systemd service (existing)
├── README.md                       # Documentation (existing)
├── VERSION                         # Version string for update detection
└── extras/
    └── 99-virtualbuddy.rules       # Optional udev rule
```

## Implementation Components

### 1. Host-Side: LinuxGuestAdditionsDiskImage.swift

New file similar to `GuestAdditionsDiskImage.swift`:

```swift
public final class LinuxGuestAdditionsDiskImage: ObservableObject {
    public static let current = LinuxGuestAdditionsDiskImage()

    // Source directory within VirtualCore bundle
    private var embeddedToolsURL: URL {
        Bundle.virtualCore.url(forResource: "LinuxGuestAdditions", withExtension: nil)
    }

    // Destination for generated ISO
    public var installedImageURL: URL {
        GuestAdditionsDiskImage.imagesRootURL
            .appendingPathComponent("VirtualBuddyLinuxTools")
            .appendingPathExtension("iso")
    }

    // Generate ISO using CreateLinuxGuestImage.sh
    public func installIfNeeded() async throws { ... }
}
```

### 2. Host-Side: CreateLinuxGuestImage.sh

```bash
#!/bin/sh
# Creates ISO from LinuxGuestAdditions directory

SOURCE_DIR="$1"
DEST_PATH="$2"
VERSION="$3"

# Write version file
echo "$VERSION" > "$SOURCE_DIR/VERSION"

# Create ISO with hdiutil
hdiutil makehybrid \
    -iso \
    -joliet \
    -joliet-volume-name "VBTOOLS" \
    -o "$DEST_PATH" \
    "$SOURCE_DIR"
```

### 3. Host-Side: LinuxVirtualMachineConfigurationHelper Changes

Add `createAdditionalBlockDevices()` override:

```swift
func createAdditionalBlockDevices() async throws -> [VZVirtioBlockDeviceConfiguration] {
    var devices = try storageDeviceContainer.additionalBlockDevices(guestType: .linux)

    // Attach Linux guest tools ISO if enabled
    if vm.configuration.guestAdditionsEnabled,
       let disk = try? VZVirtioBlockDeviceConfiguration.linuxGuestToolsDisk {
        devices.append(disk)
    }

    return devices
}
```

### 4. Guest-Side: autorun.sh

Simple entry point for users:

```bash
#!/bin/bash
# VirtualBuddy Linux Guest Tools - Quick Start
#
# Run this script with: sudo /mnt/autorun.sh
# Or use the full installer: sudo /mnt/install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "VirtualBuddy Linux Guest Tools"
echo "=============================="
echo ""
echo "This will install:"
echo "  - Automatic disk resize on boot (virtualbuddy-growfs)"
echo ""

# Check if already installed and compare versions
if [[ -f /etc/virtualbuddy/version ]]; then
    INSTALLED_VERSION=$(cat /etc/virtualbuddy/version)
    NEW_VERSION=$(cat "$SCRIPT_DIR/VERSION")

    if [[ "$INSTALLED_VERSION" == "$NEW_VERSION" ]]; then
        echo "Guest tools v$INSTALLED_VERSION already installed and up to date."
        exit 0
    else
        echo "Updating from v$INSTALLED_VERSION to v$NEW_VERSION..."
    fi
fi

# Run the full installer
exec "$SCRIPT_DIR/install.sh"
```

### 5. Guest-Side: Enhanced install.sh

Update existing install.sh to:
1. Create `/etc/virtualbuddy/` directory
2. Write version file after successful install
3. Support `--quiet` flag for non-interactive install

```bash
# Add to install.sh after successful installation:
mkdir -p /etc/virtualbuddy
cp "$SCRIPT_DIR/VERSION" /etc/virtualbuddy/version
```

## User Experience

### First Boot Flow

1. User creates new Linux VM in VirtualBuddy
2. VM boots with install ISO + guest tools ISO attached
3. After OS installation completes, user sees guest tools disk
4. User runs one command:

```bash
# Option 1: If disk is auto-mounted (most distros with desktop)
sudo /run/media/$USER/VBTOOLS/install.sh

# Option 2: Manual mount
sudo mount -L VBTOOLS /mnt
sudo /mnt/install.sh
sudo umount /mnt

# Option 3: One-liner
sudo sh -c 'mkdir -p /mnt/vbtools && mount -L VBTOOLS /mnt/vbtools && /mnt/vbtools/install.sh; umount /mnt/vbtools 2>/dev/null; rmdir /mnt/vbtools 2>/dev/null'
```

### Update Flow

1. User updates VirtualBuddy (new guest tools included)
2. On next VM boot, new ISO is attached
3. User can check for updates:

```bash
# Check if update available
INSTALLED=$(cat /etc/virtualbuddy/version 2>/dev/null || echo "none")
AVAILABLE=$(cat /run/media/$USER/VBTOOLS/VERSION 2>/dev/null || echo "none")
echo "Installed: $INSTALLED, Available: $AVAILABLE"
```

4. Re-run install.sh to update

## Configuration

### VM Settings

Add new configuration option in VBMacConfiguration:

```swift
/// Whether to attach Linux guest tools ISO to Linux VMs.
/// Defaults to true for Linux VMs.
@DecodableDefault.True
public var linuxGuestToolsEnabled = true
```

This is separate from `guestAdditionsEnabled` which controls macOS guest tools.

### UI Integration

Add toggle in VM settings:
- "Attach guest tools disk" (checkbox, default: on)
- Tooltip: "Attaches VirtualBuddy guest tools ISO for easy installation"

## File Locations

### Host (macOS)

| File | Location |
|------|----------|
| Source scripts | `VirtualCore/Resources/LinuxGuestAdditions/` |
| Generated ISO | `~/Library/Application Support/VirtualBuddy/_GuestImage/VirtualBuddyLinuxTools.iso` |
| Version digest | `~/Library/Application Support/VirtualBuddy/_GuestImage/.VirtualBuddyLinuxTools.digest` |

### Guest (Linux)

| File | Location |
|------|----------|
| Resize script | `/usr/local/bin/virtualbuddy-growfs` |
| systemd service | `/etc/systemd/system/virtualbuddy-growfs.service` |
| Version file | `/etc/virtualbuddy/version` |
| Config (future) | `/etc/virtualbuddy/config` |

## Implementation Phases

### Phase 2a: Basic ISO Attachment (MVP)
1. Create `CreateLinuxGuestImage.sh`
2. Create `LinuxGuestAdditionsDiskImage.swift`
3. Modify `LinuxVirtualMachineConfigurationHelper` to attach ISO
4. Update `install.sh` to write version file
5. Add `autorun.sh` convenience script

### Phase 2b: Polish
1. Add UI toggle for guest tools attachment
2. Add version checking in guest
3. Desktop notification on mount (optional udev rule)
4. Update documentation

### Phase 2c: Future Enhancements
1. virtio-vsock communication channel
2. Host-triggered resize signal
3. Clipboard integration (if virtio-clipboard becomes available)
4. Time synchronization helper

## Testing Checklist

- [ ] ISO generates correctly on app launch
- [ ] ISO attaches to Linux VMs
- [ ] ISO does NOT attach to macOS VMs
- [ ] Install works on Fedora (LUKS+LVM+Btrfs)
- [ ] Install works on Ubuntu (ext4)
- [ ] Install works on Debian (ext4/LVM)
- [ ] Version detection works
- [ ] Update flow works
- [ ] Resize works after reboot

## Security Considerations

1. **ISO is read-only** - Prevents tampering from guest
2. **Scripts run as root** - Required for system modifications
3. **No network required** - Reduces attack surface
4. **Version verification** - Ensures tools match host version

## References

- [VirtualBox Guest Additions](https://www.virtualbox.org/manual/ch04.html)
- [VMware Tools](https://docs.vmware.com/en/VMware-Tools/index.html)
- [cloud-init NoCloud](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html)
