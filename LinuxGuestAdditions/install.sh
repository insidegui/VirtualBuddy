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

# Check if we're in a desktop environment
HAS_DESKTOP=false
if [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    HAS_DESKTOP=true
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

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

die() {
    echo -e "${RED}${BOLD}ERROR:${NC} $*" >&2
    exit 1
}

# Send desktop notification if available
notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"  # low, normal, critical

    if $HAS_DESKTOP && command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -i "drive-harddisk" "VirtualBuddy: $title" "$message" 2>/dev/null || true
    fi
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
    log_step "Checking dependencies..."
    local missing=()

    # Check for required tools
    if ! command -v growpart &>/dev/null; then
        missing+=("growpart (cloud-guest-utils)")
    else
        log_success "growpart found"
    fi

    if command -v resize2fs &>/dev/null; then
        log_success "resize2fs found"
    elif command -v xfs_growfs &>/dev/null; then
        log_success "xfs_growfs found"
    else
        missing+=("resize2fs or xfs_growfs (e2fsprogs or xfsprogs)")
    fi

    if ! command -v cryptsetup &>/dev/null; then
        log_warning "cryptsetup not found - LUKS support will be disabled"
    else
        log_success "cryptsetup found"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Missing dependencies:${NC}"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Install them with:"

        if command -v dnf &>/dev/null; then
            echo -e "  ${BOLD}sudo dnf install cloud-utils-growpart${NC}"
        elif command -v apt-get &>/dev/null; then
            echo -e "  ${BOLD}sudo apt-get install cloud-guest-utils${NC}"
        elif command -v pacman &>/dev/null; then
            echo -e "  ${BOLD}sudo pacman -S cloud-guest-utils${NC}"
        elif command -v zypper &>/dev/null; then
            echo -e "  ${BOLD}sudo zypper install growpart${NC}"
        fi

        die "Please install missing dependencies and try again."
    fi
    echo ""
}

install_files() {
    log_step "Installing VirtualBuddy Guest Additions v$VERSION..."

    # Install the growfs script
    log "Installing virtualbuddy-growfs to /usr/local/bin/"
    install -m 755 "$SCRIPT_DIR/virtualbuddy-growfs" /usr/local/bin/virtualbuddy-growfs
    log_success "Installed virtualbuddy-growfs"

    # Install the notification script
    log "Installing notification script..."
    install -m 755 "$SCRIPT_DIR/virtualbuddy-notify" /usr/local/bin/virtualbuddy-notify
    log_success "Installed virtualbuddy-notify"

    # Install the systemd system service
    log "Installing systemd system service..."
    install -m 644 "$SCRIPT_DIR/virtualbuddy-growfs.service" /etc/systemd/system/virtualbuddy-growfs.service
    log_success "Installed growfs service"

    # Install the systemd user service for notifications
    log "Installing systemd user service for notifications..."
    mkdir -p /etc/systemd/user
    install -m 644 "$SCRIPT_DIR/virtualbuddy-notify.service" /etc/systemd/user/virtualbuddy-notify.service
    log_success "Installed notification service"

    # Reload systemd
    log "Reloading systemd daemon..."
    systemctl daemon-reload
    log_success "Reloaded systemd"

    # Enable the system service
    log "Enabling virtualbuddy-growfs service..."
    systemctl enable virtualbuddy-growfs.service
    log_success "Enabled growfs service for automatic startup"

    # Enable the user service globally (for all users)
    log "Enabling notification service for desktop users..."
    systemctl --global enable virtualbuddy-notify.service 2>/dev/null || true
    log_success "Enabled notification service"

    # Write version file for update detection
    mkdir -p /etc/virtualbuddy
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cp "$SCRIPT_DIR/VERSION" /etc/virtualbuddy/version
    else
        echo "$VERSION" > /etc/virtualbuddy/version
    fi
    log_success "Saved version info"
    echo ""
}

run_now() {
    echo ""
    echo -e "${BOLD}Would you like to resize the filesystem now?${NC}"
    echo "This will expand the root partition if the disk has been enlarged."
    echo ""
    read -p "Resize now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        log_step "Running filesystem resize..."
        /usr/local/bin/virtualbuddy-growfs --verbose
    else
        echo ""
        log "Skipped. The filesystem will be automatically resized on next boot."
    fi
}

show_status() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║         VirtualBuddy Guest Additions Installed!              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "The virtualbuddy-growfs service will automatically run on each boot"
    echo "to expand the filesystem if the disk has been resized in VirtualBuddy."
    echo ""
    echo -e "${BOLD}Manual commands:${NC}"
    echo -e "  ${CYAN}Check status:${NC}     systemctl status virtualbuddy-growfs"
    echo -e "  ${CYAN}Run manually:${NC}     sudo virtualbuddy-growfs --verbose"
    echo -e "  ${CYAN}View logs:${NC}        journalctl -u virtualbuddy-growfs"
    echo -e "  ${CYAN}Uninstall:${NC}        sudo $SCRIPT_DIR/uninstall.sh"

    # Send desktop notification
    notify "Installation Complete" "VirtualBuddy Guest Additions have been installed successfully."
}

show_banner() {
    echo ""
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}║          VirtualBuddy Linux Guest Additions v$VERSION          ║${NC}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will install automatic disk resize support for your VM."
    echo "When you resize the disk in VirtualBuddy, the filesystem will"
    echo "automatically expand on the next boot."
    echo ""
}

main() {
    show_banner
    check_root
    check_systemd
    check_dependencies
    install_files
    show_status
    run_now

    echo ""
    echo -e "${GREEN}${BOLD}All done!${NC} Enjoy using VirtualBuddy."
    echo ""
}

main "$@"
