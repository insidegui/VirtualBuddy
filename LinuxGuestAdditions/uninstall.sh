#!/bin/bash
#
# VirtualBuddy Linux Guest Additions Uninstaller
#

set -euo pipefail

# Colors for terminal output (disabled if not a TTY)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

log() {
    echo -e "${CYAN}[virtualbuddy]${NC} $*"
}

log_step() {
    echo -e "${BLUE}${BOLD}==>${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

die() {
    echo -e "${RED}${BOLD}ERROR:${NC} $*" >&2
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (try: sudo $0)"
    fi
}

main() {
    echo ""
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║          VirtualBuddy Guest Additions Uninstaller            ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root

    log_step "Disabling services..."

    # Disable and stop the growfs service
    if systemctl is-enabled virtualbuddy-growfs.service &>/dev/null; then
        systemctl disable virtualbuddy-growfs.service
        log_success "Disabled virtualbuddy-growfs service"
    fi

    if systemctl is-active virtualbuddy-growfs.service &>/dev/null; then
        systemctl stop virtualbuddy-growfs.service
        log_success "Stopped virtualbuddy-growfs service"
    fi

    # Disable the user notification service globally
    if systemctl --global is-enabled virtualbuddy-notify.service &>/dev/null 2>&1; then
        systemctl --global disable virtualbuddy-notify.service 2>/dev/null || true
        log_success "Disabled notification service"
    fi

    echo ""
    log_step "Removing files..."

    # Remove system service files
    if [[ -f /etc/systemd/system/virtualbuddy-growfs.service ]]; then
        rm -f /etc/systemd/system/virtualbuddy-growfs.service
        log_success "Removed growfs service file"
    fi

    # Remove user service file
    if [[ -f /etc/systemd/user/virtualbuddy-notify.service ]]; then
        rm -f /etc/systemd/user/virtualbuddy-notify.service
        log_success "Removed notification service file"
    fi

    # Remove scripts
    if [[ -f /usr/local/bin/virtualbuddy-growfs ]]; then
        rm -f /usr/local/bin/virtualbuddy-growfs
        log_success "Removed virtualbuddy-growfs"
    fi

    if [[ -f /usr/local/bin/virtualbuddy-notify ]]; then
        rm -f /usr/local/bin/virtualbuddy-notify
        log_success "Removed virtualbuddy-notify"
    fi

    # Remove status file
    rm -f /var/run/virtualbuddy-growfs.status 2>/dev/null || true

    # Remove version/config directory
    if [[ -d /etc/virtualbuddy ]]; then
        rm -rf /etc/virtualbuddy
        log_success "Removed VirtualBuddy config directory"
    fi

    # Reload systemd
    log "Reloading systemd..."
    systemctl daemon-reload
    log_success "Reloaded systemd"

    echo ""
    echo -e "${GREEN}${BOLD}Uninstallation complete!${NC}"
    echo ""
    echo "VirtualBuddy Guest Additions have been removed from your system."
    echo ""
}

main "$@"
