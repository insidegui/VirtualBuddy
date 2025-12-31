#!/bin/bash
#
# VirtualBuddy Linux Guest Additions Installer
#
# This script installs the VirtualBuddy guest additions for Linux,
# which provides automatic filesystem resize after disk expansion.
#
# Supports: Fedora, Ubuntu, Debian, Arch, and other systemd-based distros
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.1.0"

log() {
    echo "[virtualbuddy-install] $*"
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

check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        die "systemd not found. This installer requires a systemd-based distribution."
    fi
}

check_dependencies() {
    local missing=()

    # Check for required tools
    if ! command -v growpart &>/dev/null; then
        missing+=("growpart (cloud-guest-utils)")
    fi

    if ! command -v resize2fs &>/dev/null && ! command -v xfs_growfs &>/dev/null; then
        missing+=("resize2fs or xfs_growfs (e2fsprogs or xfsprogs)")
    fi

    if ! command -v cryptsetup &>/dev/null; then
        log "WARNING: cryptsetup not found. LUKS support will be disabled."
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Missing dependencies:"
        for dep in "${missing[@]}"; do
            log "  - $dep"
        done
        log ""
        log "Install them with:"

        if command -v dnf &>/dev/null; then
            log "  sudo dnf install cloud-utils-growpart"
        elif command -v apt-get &>/dev/null; then
            log "  sudo apt-get install cloud-guest-utils"
        elif command -v pacman &>/dev/null; then
            log "  sudo pacman -S cloud-guest-utils"
        elif command -v zypper &>/dev/null; then
            log "  sudo zypper install growpart"
        fi

        die "Please install missing dependencies and try again."
    fi
}

install_files() {
    log "Installing VirtualBuddy Guest Additions v$VERSION..."

    # Install the growfs script
    log "Installing virtualbuddy-growfs to /usr/local/bin/"
    install -m 755 "$SCRIPT_DIR/virtualbuddy-growfs" /usr/local/bin/virtualbuddy-growfs

    # Install the systemd service
    log "Installing systemd service..."
    install -m 644 "$SCRIPT_DIR/virtualbuddy-growfs.service" /etc/systemd/system/virtualbuddy-growfs.service

    # Reload systemd
    log "Reloading systemd..."
    systemctl daemon-reload

    # Enable the service
    log "Enabling virtualbuddy-growfs service..."
    systemctl enable virtualbuddy-growfs.service

    # Write version file for update detection
    log "Writing version info..."
    mkdir -p /etc/virtualbuddy
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cp "$SCRIPT_DIR/VERSION" /etc/virtualbuddy/version
    else
        echo "$VERSION" > /etc/virtualbuddy/version
    fi
}

run_now() {
    log ""
    read -p "Would you like to run the filesystem grow now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Running virtualbuddy-growfs..."
        /usr/local/bin/virtualbuddy-growfs --verbose
    fi
}

show_status() {
    log ""
    log "Installation complete!"
    log ""
    log "The virtualbuddy-growfs service will automatically run on each boot"
    log "to expand the filesystem if the disk has been resized."
    log ""
    log "Manual commands:"
    log "  Check status:     systemctl status virtualbuddy-growfs"
    log "  Run manually:     sudo virtualbuddy-growfs --verbose"
    log "  View logs:        journalctl -u virtualbuddy-growfs"
    log "  Uninstall:        sudo $SCRIPT_DIR/uninstall.sh"
}

main() {
    log "VirtualBuddy Linux Guest Additions Installer"
    log ""

    check_root
    check_systemd
    check_dependencies
    install_files
    show_status
    run_now
}

main "$@"
