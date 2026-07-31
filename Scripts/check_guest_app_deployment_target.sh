#!/usr/bin/env zsh

# This script prevents raising the deployment target for VirtualBuddyGuest without placing the corresponding legacy archive in data/LegacyGuest,
# ensuring that older releases are always made available to users running legacy guest OSes

set -e

source "Scripts/legacy_guest_env.zsh"

# This only runs for builds using Managed configurations (Beta configurations are also managed)
if [[ "$CONFIGURATION" == *"Managed"* || "$CONFIGURATION" == *"Beta"* ]]; then
    EXPECTED_GUEST_ARCHIVE="${SRCROOT}/${LEGACY_GUEST_ARCHIVE_DIR}/VirtualBuddyGuest_minOS_${LATEST_LEGACY_GUEST_APP_ARCHIVE_DEPLOYMENT_TARGET}.dmg"

    if [ ! -f "${EXPECTED_GUEST_ARCHIVE}" ]; then
        echo "error: The deployment target for VirtualBuddyGuest has been raised to ${MACOSX_DEPLOYMENT_TARGET} without a legacy archive being created for the latest version that supported ${LATEST_LEGACY_GUEST_APP_ARCHIVE_DEPLOYMENT_TARGET}. Please use dmgdist against a notarized build of VirtualBuddyGuest to generate an archive and register it with vctool before proceeding with this release."
        exit 1
    fi
fi
