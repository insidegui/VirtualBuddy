#!/usr/bin/env zsh

set -e

source "Scripts/legacy_guest_env.zsh"

GUEST_APP_BUNDLE="${1}"

echoerr () {
	echo "$1" >&2
}

if [ -z "${GUEST_APP_BUNDLE}" ]; then
    echoerr "Usage: $0 path/to/notarized/VirtualBuddyGuest.app\n"
    echoerr "This command takes a notarized VirtualBuddyGuest.app and produces an Apple Archive named 'VirtualBuddyGuest_minOS_<version>.aar' (example: 'VirtualBuddyGuest_minOS_13.0.aar')."
    echoerr "The generated archive is offered via the VirtualBuddy software catalog so that clients running older guest OSes can still use the guest app.\n"
    exit 64
fi

if [ ! -d "${GUEST_APP_BUNDLE}" ]; then
    echoerr "Guest app bundle doesn't exist at ${GUEST_APP_BUNDLE}"
    exit 1
fi

BUNDLE_NAME=$(basename "${GUEST_APP_BUNDLE}")

echoerr "Verifying notarization of ${GUEST_APP_BUNDLE}"

spctl --verbose=4 --assess "${GUEST_APP_BUNDLE}"

if [ $? -ne 0 ]; then
    echoerr "ERROR: Guest app bundle is not notarized/stapled"
    exit 1
fi

echoerr "\nExtracting minimum OS version"

VERSION_KEY="LSMinimumSystemVersion"

MIN_VERSION=$(/usr/libexec/PlistBuddy -c "Print :${VERSION_KEY}" "${GUEST_APP_BUNDLE}/Contents/Info.plist")

if [ -z "${MIN_VERSION}" ]; then
    echoerr "ERROR: Failed to extract ${VERSION_KEY} from guest app bundle"
    exit 1
fi 

OUTDIR=$(mktemp -d)
# Paranoid because we might rm -Rf this later...
if [ ! -d "${OUTDIR}" ]; then
    echoerr "ERROR: Failed to create a temporary directory"
    exit 1
fi

ARCHIVE_NAME="VirtualBuddyGuest_minOS_${MIN_VERSION}.aar"
OUTPUT="${OUTDIR}/${ARCHIVE_NAME}"

echoerr "\nCreating ${ARCHIVE_NAME}"

aa archive -D "${GUEST_APP_BUNDLE}" -o "${OUTPUT}"

echoerr "\nVerifying that notarization is retained by the archive..."

EXTRACTDIR=$(mktemp -d)
# Paranoid because we will rm -Rf this later...
if [ ! -d "${EXTRACTDIR}" ]; then
    echoerr "ERROR: Failed to create a temporary directory"
    exit 1
fi

aa extract -i "${OUTPUT}" -d "${EXTRACTDIR}"

if [ ! -d "${EXTRACTDIR}/${BUNDLE_NAME}" ]; then
    echoerr "ERROR: Failed to extract archive for validation"
    exit 1
fi

spctl --verbose=4 --assess "${EXTRACTDIR}/${BUNDLE_NAME}"

if [ $? -ne 0 ]; then
    echoerr "ERROR: Guest app failed notarization check after archival/extraction, archive would not have worked."
    rm -Rf "${OUTPUT}" || true
    rm -Rf "${EXTRACTDIR}" || true
    exit 1
fi

rm -Rf "${EXTRACTDIR}" 2>/dev/null || true

cp -cf "${OUTPUT}" "${LEGACY_GUEST_ARCHIVE_DIR}/"

echoerr "\n✅ Archive created and verified!\n"

echoerr "You may now set LATEST_LEGACY_GUEST_APP_ARCHIVE_DEPLOYMENT_TARGET=\"${MIN_VERSION}\" in Scripts/legacy_guest_env.zsh\n"
