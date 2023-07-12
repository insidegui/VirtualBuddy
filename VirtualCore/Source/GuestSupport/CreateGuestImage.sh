#!/bin/sh

: '
This script is used by VirtualBuddy to dynamically generate a disk image that can be mounted in a virtual machine,
containing the current version of the VirtualBuddyGuest app embedded into VirtualBuddy itself.

Images are stored in ~/Library/Application Support/VirtualBuddy/_GuestImage.

Alongside the images, the app stores a digest of the entire contents of the Guest app bundle,
so that it can be automatically updated whenever something changes in the Guest app.
'

GUEST_APP_PATH="$1"
GUEST_APP_DIGEST="$2"
GUEST_DMG_SUFFIX="$3"

if [ -z "$GUEST_APP_PATH" ]; then
    echo "Shell script invocation error: missing GUEST_APP_PATH value as first argument" 1>&2
    exit 7
fi

if [ -z "$GUEST_APP_DIGEST" ]; then
    echo "Shell script invocation error: missing GUEST_APP_DIGEST value as second argument" 1>&2
    exit 7
fi

if [ ! -d "$GUEST_APP_PATH" ]; then
    echo "Shell script invocation error: guest app bundle doesn't exist at $GUEST_APP_PATH" 1>&2
    exit 7
fi

VBROOT="$HOME/Library/Application Support/VirtualBuddy"
GUEST_DMG_DEST_PATH="$VBROOT/_GuestImage"

GUEST_DMG_NAME="VirtualBuddyGuest$GUEST_DMG_SUFFIX"

GUEST_STAGING_PATH="$GUEST_DMG_DEST_PATH/staging"
GUEST_TEMP_MOUNT_PATH="$GUEST_STAGING_PATH/VirtualBuddyGuest$GUEST_DMG_SUFFIX"
GUEST_TEMP_DMG_PATH="$GUEST_STAGING_PATH/$GUEST_DMG_NAME.dmg"

GUEST_TEMP_DIGEST_PATH="$GUEST_TEMP_MOUNT_PATH/.$GUEST_DMG_NAME.digest"

# Make sure the temporary mount point exists

mkdir -p "$GUEST_TEMP_MOUNT_PATH" 2>/dev/null || echo ""

# Unmount and remove any leftovers from previous script invocation

hdiutil detach -force "$GUEST_TEMP_MOUNT_PATH" 2>/dev/null || echo ""

rm "$GUEST_TEMP_DMG_PATH" 2>/dev/null || echo ""

# Create blank disk image

hdiutil create -layout MBRSPUD -size 20M -fs HFS+ -volname Guest "$GUEST_TEMP_DMG_PATH" || \
    { echo "Failed to create VirtualBuddyGuest disk image: hdiutil exit code $?" 1>&2; exit 1; }

# Mount image at staging location

hdiutil attach -imagekey diskimage-class=CRawDiskImage -noverify "$GUEST_TEMP_DMG_PATH" -mountpoint "$GUEST_TEMP_MOUNT_PATH" || \
    { echo "Failed to mount empty VirtualBuddyGuest disk image: hdiutil exit code $?" 1>&2; exit 1; }
    
# Write digest to temporary mount

echo "$GUEST_APP_DIGEST" > "$GUEST_TEMP_DIGEST_PATH"

# Copy VirtualBuddyGuest.app into the temporary mount

cp -R "$GUEST_APP_PATH" "$GUEST_TEMP_MOUNT_PATH/" || \
    { echo "Failed to copy VirtualBuddyGuest.app into disk image: exit code $?" 1>&2; exit 1; }

# Copy the digest to its final destination
    
yes | cp -rf "$GUEST_TEMP_DIGEST_PATH" "$GUEST_DMG_DEST_PATH" || \
    { echo "Failed to copy guest digest: exit code $?" 1>&2; } # Failure to copy digest is non-fatal

# Eject the disk image

hdiutil detach -force "$GUEST_TEMP_MOUNT_PATH" || \
    { echo "Failed to eject VirtualBuddyGuest disk image: exit code $?" 1>&2; exit 1; }

# Remove any extended attributes from the disk image

xattr -cr "$GUEST_TEMP_DMG_PATH" 2>/dev/null || echo ""

# Copy the finalized disk image to its final destination

yes | cp -rf "$GUEST_TEMP_DMG_PATH" "$GUEST_DMG_DEST_PATH" || \
    { echo "Failed to copy finalized disk image: exit code $?" 1>&2; exit 1; }

# Cleanup

rm "$GUEST_TEMP_DMG_PATH" 2>/dev/null || echo ""
rm -Rf "$GUEST_TEMP_MOUNT_PATH" 2>/dev/null || echo ""
rm -Rf "$GUEST_STAGING_PATH" 2>/dev/null || echo ""

echo "OK"