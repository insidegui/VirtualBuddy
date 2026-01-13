#!/bin/bash
#
# VirtualBuddy Linux Guest Tools - Quick Start
#
# Run this script with: sudo /path/to/autorun.sh
# Or use the full installer: sudo /path/to/install.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "VirtualBuddy Linux Guest Tools"
echo "=============================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    echo ""
    echo "Usage: sudo $0"
    exit 1
fi

# Check if already installed and compare versions
if [[ -f /etc/virtualbuddy/version ]]; then
    INSTALLED_VERSION=$(cat /etc/virtualbuddy/version 2>/dev/null || echo "unknown")

    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        NEW_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
    else
        # Fallback to version from install.sh
        NEW_VERSION=$(grep '^VERSION=' "$SCRIPT_DIR/install.sh" 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    fi

    if [[ "$INSTALLED_VERSION" == "$NEW_VERSION" ]]; then
        echo "Guest tools already installed and up to date."
        echo "Version: $INSTALLED_VERSION"
        echo ""
        echo "To reinstall, run: sudo $SCRIPT_DIR/install.sh"
        echo "To uninstall, run: sudo $SCRIPT_DIR/uninstall.sh"
        exit 0
    else
        echo "Update available!"
        echo "  Installed: $INSTALLED_VERSION"
        echo "  Available: $NEW_VERSION"
        echo ""
    fi
else
    echo "Guest tools not yet installed."
    echo ""
fi

echo "This will install:"
echo "  - virtualbuddy-growfs: Automatic disk resize on boot"
echo "  - systemd service to run resize automatically"
echo ""

# Run the full installer
exec "$SCRIPT_DIR/install.sh"
