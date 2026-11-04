#!/bin/sh
set -eu

# The guest app is signed before embedding. Stripping headers or modules from
# its nested frameworks after that point invalidates their resource seals.
guest_app="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/SharedSupport/VirtualBuddyGuest.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$guest_app"
