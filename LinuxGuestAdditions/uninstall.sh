#!/bin/bash
#
# VirtualBuddy Linux Guest Additions Uninstaller
#

set -euo pipefail

log() {
    echo "[virtualbuddy-uninstall] $*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (try: sudo $0)"
    fi
}

main() {
    log "VirtualBuddy Linux Guest Additions Uninstaller"
    log ""

    check_root

    # Disable and stop the service
    if systemctl is-enabled virtualbuddy-growfs.service &>/dev/null; then
        log "Disabling virtualbuddy-growfs service..."
        systemctl disable virtualbuddy-growfs.service
    fi

    if systemctl is-active virtualbuddy-growfs.service &>/dev/null; then
        log "Stopping virtualbuddy-growfs service..."
        systemctl stop virtualbuddy-growfs.service
    fi

    # Remove files
    if [[ -f /etc/systemd/system/virtualbuddy-growfs.service ]]; then
        log "Removing systemd service file..."
        rm -f /etc/systemd/system/virtualbuddy-growfs.service
    fi

    if [[ -f /usr/local/bin/virtualbuddy-growfs ]]; then
        log "Removing virtualbuddy-growfs script..."
        rm -f /usr/local/bin/virtualbuddy-growfs
    fi

    # Reload systemd
    log "Reloading systemd..."
    systemctl daemon-reload

    log ""
    log "Uninstallation complete!"
}

main "$@"
