#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO_URL="https://github.com/KangweiZhu/lyrics-on-panel"
INSTALL_DIR="$HOME/.local/share/lyrics-on-panel"
INSTALL_PARENT="$(dirname "$INSTALL_DIR")"
SERVICE_NAME="Universal-Mpris-LyricServer"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/${SERVICE_NAME}.service"

TEMP_DIR=""
BACKUP_DIR=""
OLD_INSTALL_PRESENT=false
OLD_SERVICE_PRESENT=false
OLD_SERVICE_ENABLED=false
SWAPPED=false

cleanup() {
    local status=$?
    trap - EXIT

    if [ "$status" -ne 0 ] && [ "$SWAPPED" = true ]; then
        echo -e "${YELLOW}Installation failed; restoring the previous installation...${NC}"
        systemctl --user stop "${SERVICE_NAME}.service" 2>/dev/null || true
        rm -rf -- "$INSTALL_DIR"
        if [ "$OLD_INSTALL_PRESENT" = true ] && [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
            mv -- "$BACKUP_DIR" "$INSTALL_DIR"
            BACKUP_DIR=""
        fi
        if [ "$OLD_SERVICE_PRESENT" = true ]; then
            cp -- "$TEMP_DIR/previous.service" "$SERVICE_FILE"
        else
            rm -f -- "$SERVICE_FILE"
        fi
        systemctl --user daemon-reload 2>/dev/null || true
        if [ "$OLD_SERVICE_ENABLED" = true ]; then
            systemctl --user enable "${SERVICE_NAME}.service" 2>/dev/null || true
        else
            systemctl --user disable "${SERVICE_NAME}.service" 2>/dev/null || true
        fi
        if [ "$OLD_INSTALL_PRESENT" = true ]; then
            systemctl --user restart "${SERVICE_NAME}.service" 2>/dev/null || true
        fi
    fi

    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        rm -rf -- "$BACKUP_DIR"
    fi
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf -- "$TEMP_DIR"
    fi
    exit "$status"
}
trap cleanup EXIT

echo -e "${GREEN}=== Lyrics-on-Panel Backend Installer ===${NC}"

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run as root${NC}"
    exit 1
fi

echo -e "\n${YELLOW}[1/4] Installing system build dependencies...${NC}"
sudo pacman -S --needed --noconfirm base-devel cmake dbus git rust

echo -e "\n${YELLOW}[2/4] Cloning project into a temporary directory...${NC}"
mkdir -p -- "$INSTALL_PARENT"
TEMP_DIR="$(mktemp -d "$INSTALL_PARENT/.lyrics-on-panel.install.XXXXXX")"
git clone --depth 1 "$REPO_URL" "$TEMP_DIR/repo"

echo -e "\n${YELLOW}[3/4] Building Rust backend...${NC}"
cargo build --release --locked --manifest-path "$TEMP_DIR/repo/backend/Cargo.toml"

echo -e "\n${YELLOW}[4/4] Installing and starting systemd service...${NC}"
mkdir -p -- "$INSTALL_PARENT" "$SERVICE_DIR"
if [ -e "$SERVICE_FILE" ]; then
    cp -- "$SERVICE_FILE" "$TEMP_DIR/previous.service"
    OLD_SERVICE_PRESENT=true
fi
if systemctl --user is-enabled --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    OLD_SERVICE_ENABLED=true
fi
if [ -e "$INSTALL_DIR" ]; then
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}Error: $INSTALL_DIR exists and is not a directory${NC}"
        exit 1
    fi
    BACKUP_DIR="$(mktemp -d "$INSTALL_PARENT/.lyrics-on-panel.backup.XXXXXX")"
    rmdir -- "$BACKUP_DIR"
    mv -- "$INSTALL_DIR" "$BACKUP_DIR"
    OLD_INSTALL_PRESENT=true
    SWAPPED=true
fi
mv -- "$TEMP_DIR/repo" "$INSTALL_DIR"
SWAPPED=true

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Lyrics-on-Panel MPRIS2 Backend
After=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/backend/target/release/lyrics-on-panel-backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable "${SERVICE_NAME}.service"
if ! systemctl --user restart "${SERVICE_NAME}.service" || \
    ! systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
    systemctl --user status --no-pager "${SERVICE_NAME}.service" || true
    echo -e "${RED}Error: Backend service failed to start${NC}"
    exit 1
fi
systemctl --user status --no-pager "${SERVICE_NAME}.service"

SWAPPED=false
if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    rm -rf -- "$BACKUP_DIR"
    BACKUP_DIR=""
fi

echo -e "\n${GREEN}=== Installation Complete ===${NC}"
echo "Service: systemctl --user status ${SERVICE_NAME}"
echo "Logs:    journalctl --user -u ${SERVICE_NAME} -f"
echo "Backend: ws://127.0.0.1:23560"
