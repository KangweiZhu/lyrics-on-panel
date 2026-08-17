#!/bin/bash
set -euo pipefail

SERVICE_NAME="Universal-Mpris-LyricServer-Rust"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"
MANIFEST="$REPO_DIR/backend-rust/Cargo.toml"
SOURCE_BINARY="$REPO_DIR/backend-rust/target/release/lyrics-on-panel-backend"
INSTALL_DIR="$HOME/.local/libexec/lyrics-on-panel-rust"
INSTALL_BINARY="$INSTALL_DIR/lyrics-on-panel-backend"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/${SERVICE_NAME}.service"
TEMP_DIR="$(mktemp -d)"
OLD_SERVICE_PRESENT=false
OLD_BINARY_PRESENT=false
OLD_SERVICE_ACTIVE=false
OLD_SERVICE_ENABLED=false
INSTALLED=false

cleanup() {
    local status=$?
    trap - EXIT

    if [ "$status" -ne 0 ] && [ "$INSTALLED" = true ]; then
        echo "Installation failed; restoring the previous Rust backend..." >&2
        systemctl --user stop "${SERVICE_NAME}.service" 2>/dev/null || true

        if [ "$OLD_BINARY_PRESENT" = true ]; then
            install -Dm755 "$TEMP_DIR/previous-binary" "$INSTALL_BINARY"
        else
            rm -f -- "$INSTALL_BINARY"
        fi

        if [ "$OLD_SERVICE_PRESENT" = true ]; then
            install -Dm644 "$TEMP_DIR/previous.service" "$SERVICE_FILE"
        else
            rm -f -- "$SERVICE_FILE"
        fi

        systemctl --user daemon-reload 2>/dev/null || true
        if [ "$OLD_SERVICE_ENABLED" = true ]; then
            systemctl --user enable "${SERVICE_NAME}.service" 2>/dev/null || true
        else
            systemctl --user disable "${SERVICE_NAME}.service" 2>/dev/null || true
        fi
        if [ "$OLD_SERVICE_ACTIVE" = true ]; then
            systemctl --user restart "${SERVICE_NAME}.service" 2>/dev/null || true
        fi
    fi

    rm -rf -- "$TEMP_DIR"
    exit "$status"
}
trap cleanup EXIT

if ! command -v cargo >/dev/null 2>&1; then
    echo "Error: cargo is required. On Arch Linux, install it with: sudo pacman -S rust" >&2
    exit 1
fi

echo "Building the Rust backend from $REPO_DIR..."
cargo build --release --locked --manifest-path "$MANIFEST"

if [ ! -x "$SOURCE_BINARY" ]; then
    echo "Error: release binary was not created at $SOURCE_BINARY" >&2
    exit 1
fi

mkdir -p -- "$INSTALL_DIR" "$SERVICE_DIR"
if [ -f "$SERVICE_FILE" ]; then
    cp -- "$SERVICE_FILE" "$TEMP_DIR/previous.service"
    OLD_SERVICE_PRESENT=true
fi
if [ -f "$INSTALL_BINARY" ]; then
    cp -- "$INSTALL_BINARY" "$TEMP_DIR/previous-binary"
    OLD_BINARY_PRESENT=true
fi
if systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
    OLD_SERVICE_ACTIVE=true
fi
if systemctl --user is-enabled --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
    OLD_SERVICE_ENABLED=true
fi

install -Dm755 "$SOURCE_BINARY" "$TEMP_DIR/lyrics-on-panel-backend"
mv -f -- "$TEMP_DIR/lyrics-on-panel-backend" "$INSTALL_BINARY"

cat > "$TEMP_DIR/service" <<EOF
[Unit]
Description=Lyrics-on-Panel MPRIS2 Backend
After=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_BINARY
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
install -Dm644 "$TEMP_DIR/service" "$SERVICE_FILE"
INSTALLED=true

systemctl --user daemon-reload
systemctl --user enable "${SERVICE_NAME}.service"
systemctl --user restart "${SERVICE_NAME}.service"

if ! systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
    systemctl --user status --no-pager "${SERVICE_NAME}.service" || true
    exit 1
fi

INSTALLED=false
echo "Installed the Rust backend from the current checkout successfully."
echo "Binary:  $INSTALL_BINARY"
echo "Service: systemctl --user status ${SERVICE_NAME}.service"
echo "Logs:    journalctl --user -u ${SERVICE_NAME}.service -f"
