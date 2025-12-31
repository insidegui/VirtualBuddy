#!/bin/sh

: '
This script is used by VirtualBuddy to dynamically generate an ISO disk image
containing the Linux guest tools that can be mounted in a Linux virtual machine.

Images are stored in ~/Library/Application Support/VirtualBuddy/_GuestImage.

Alongside the images, the app stores a digest of the contents,
so that it can be automatically updated whenever something changes.
'

SOURCE_DIR="$1"
DEST_PATH="$2"
DIGEST="$3"

if [ -z "$SOURCE_DIR" ]; then
    echo "Shell script invocation error: missing SOURCE_DIR value as first argument" 1>&2
    exit 7
fi

if [ -z "$DEST_PATH" ]; then
    echo "Shell script invocation error: missing DEST_PATH value as second argument" 1>&2
    exit 7
fi

if [ -z "$DIGEST" ]; then
    echo "Shell script invocation error: missing DIGEST value as third argument" 1>&2
    exit 7
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Shell script invocation error: source directory doesn't exist at $SOURCE_DIR" 1>&2
    exit 7
fi

VBROOT="$HOME/Library/Application Support/VirtualBuddy"
GUEST_ISO_DEST_PATH="$VBROOT/_GuestImage"
STAGING_DIR="$GUEST_ISO_DEST_PATH/staging-linux"

# Ensure destination directory exists
mkdir -p "$GUEST_ISO_DEST_PATH" 2>/dev/null || true

# Clean up any previous staging directory
rm -rf "$STAGING_DIR" 2>/dev/null || true
mkdir -p "$STAGING_DIR"

# Copy source files to staging (excluding DESIGN.md and other non-essential files)
cp "$SOURCE_DIR/install.sh" "$STAGING_DIR/"
cp "$SOURCE_DIR/uninstall.sh" "$STAGING_DIR/"
cp "$SOURCE_DIR/virtualbuddy-growfs" "$STAGING_DIR/"
cp "$SOURCE_DIR/virtualbuddy-growfs.service" "$STAGING_DIR/"
cp "$SOURCE_DIR/README.md" "$STAGING_DIR/"

# Write version/digest file
echo "$DIGEST" > "$STAGING_DIR/VERSION"

# Create autorun.sh if it doesn't exist in source
if [ ! -f "$SOURCE_DIR/autorun.sh" ]; then
    cat > "$STAGING_DIR/autorun.sh" << 'AUTORUN_EOF'
#!/bin/bash
#
# VirtualBuddy Linux Guest Tools - Quick Start
#
# Run this script with: sudo /path/to/autorun.sh
# Or use the full installer: sudo /path/to/install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "VirtualBuddy Linux Guest Tools"
echo "=============================="
echo ""

# Check if already installed and compare versions
if [[ -f /etc/virtualbuddy/version ]]; then
    INSTALLED_VERSION=$(cat /etc/virtualbuddy/version 2>/dev/null)
    NEW_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null)

    if [[ "$INSTALLED_VERSION" == "$NEW_VERSION" ]]; then
        echo "Guest tools already installed and up to date."
        echo "Version: $INSTALLED_VERSION"
        echo ""
        echo "To reinstall, run: sudo $SCRIPT_DIR/install.sh"
        exit 0
    else
        echo "Update available!"
        echo "Installed: $INSTALLED_VERSION"
        echo "Available: $NEW_VERSION"
        echo ""
    fi
fi

# Run the full installer
exec "$SCRIPT_DIR/install.sh"
AUTORUN_EOF
    chmod +x "$STAGING_DIR/autorun.sh"
else
    cp "$SOURCE_DIR/autorun.sh" "$STAGING_DIR/"
fi

# Make scripts executable
chmod +x "$STAGING_DIR/install.sh"
chmod +x "$STAGING_DIR/uninstall.sh"
chmod +x "$STAGING_DIR/virtualbuddy-growfs"

# Remove any existing ISO at destination
rm -f "$DEST_PATH" 2>/dev/null || true

# Create ISO using hdiutil
# -iso: Create ISO 9660 filesystem
# -joliet: Add Joliet extensions for longer filenames
# -joliet-volume-name: Set the volume name
hdiutil makehybrid \
    -iso \
    -joliet \
    -joliet-volume-name "VBTOOLS" \
    -o "$DEST_PATH" \
    "$STAGING_DIR" || {
        echo "Failed to create Linux guest tools ISO: hdiutil exit code $?" 1>&2
        rm -rf "$STAGING_DIR" 2>/dev/null || true
        exit 1
    }

# Write digest file alongside the ISO
DIGEST_PATH="${DEST_PATH%.iso}.digest"
echo "$DIGEST" > "$DIGEST_PATH"

# Cleanup staging directory
rm -rf "$STAGING_DIR" 2>/dev/null || true

echo "OK"
