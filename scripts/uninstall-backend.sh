#!/bin/bash
# Lyrics-on-Panel Uninstaller

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

INSTALL_DIR="$HOME/.local/share/lyrics-on-panel"
SERVICE_NAME="Universal-Mpris-LyricServer"

echo -e "${RED}=== Lyrics-on-Panel Uninstaller ===${NC}"

# Stop and disable service
if systemctl --user is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo "Stopping service..."
    systemctl --user stop "${SERVICE_NAME}"
fi

if systemctl --user is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo "Disabling service..."
    systemctl --user disable "${SERVICE_NAME}"
fi

# Remove service file
if [ -f "$HOME/.config/systemd/user/${SERVICE_NAME}.service" ]; then
    echo "Removing service file..."
    rm "$HOME/.config/systemd/user/${SERVICE_NAME}.service"
    systemctl --user daemon-reload
fi

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing installation directory..."
    rm -rf "$INSTALL_DIR"
fi

echo -e "\n${GREEN}Uninstallation complete${NC}"
