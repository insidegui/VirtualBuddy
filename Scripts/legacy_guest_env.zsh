#!/usr/bin/env zsh

# Path to legacy guest app archive directory relative to VirtualBuddy repo root
export LEGACY_GUEST_ARCHIVE_DIR=data/LegacyGuestApp

# The deployment target for the latest VirtualBuddyGuest app archive
# If a managed build is attempted with a different value without an archive
# existing with this version number suffix, the build fails.
export LATEST_LEGACY_GUEST_APP_ARCHIVE_DEPLOYMENT_TARGET="14.0"
