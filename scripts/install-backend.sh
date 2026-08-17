#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO_URL="https://github.com/KangweiZhu/lyrics-on-panel"
INSTALL_DIR="$HOME/.local/share/lyrics-on-panel"
SERVICE_NAME="Universal-Mpris-LyricServer"
BACKEND="${1:-}"

echo -e "${GREEN}=== Lyrics-on-Panel Backend Installer ===${NC}"

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run as root${NC}"
    exit 1
fi

if [ -z "$BACKEND" ]; then
    if [ -t 0 ]; then
        echo "Select backend implementation:"
        echo "  1) Python (default)"
        echo "  2) Rust"
        read -r -p "Choice [1]: " choice
        case "$choice" in
            ""|1) BACKEND="python" ;;
            2) BACKEND="rust" ;;
            *)
                echo -e "${RED}Error: Invalid selection${NC}"
                exit 1
                ;;
        esac
    else
        BACKEND="python"
    fi
fi

if [ "$BACKEND" != "python" ] && [ "$BACKEND" != "rust" ]; then
    echo -e "${RED}Usage: $0 [python|rust]${NC}"
    exit 1
fi

echo -e "${GREEN}Selected backend: $BACKEND${NC}"

# Todo: Debian / Nix / SUSE support
echo -e "\n${YELLOW}Installing system dependencies...${NC}"
if [ "$BACKEND" = "python" ]; then
    sudo pacman -S --needed --noconfirm git curl dbus glib2 pkgconf base-devel
else
    sudo pacman -S --needed --noconfirm git dbus base-devel cmake rust
fi

echo -e "\n${YELLOW}Cloning project...${NC}"
rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"

if [ "$BACKEND" = "python" ]; then
    echo -e "\n${YELLOW}Setting up Python backend...${NC}"
    if ! command -v uv &>/dev/null; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    echo -e "${GREEN}uv: $(uv --version)${NC}"

    cd "$INSTALL_DIR/backend"
    uv self update
    uv venv --python 3.13.11
    uv pip install websockets==15.0.1 dbus-python==1.4.0

    cat > "$INSTALL_DIR/backend/run.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source .venv/bin/activate
exec python src/server.py
EOF
    chmod +x "$INSTALL_DIR/backend/run.sh"
    EXEC_START="$INSTALL_DIR/backend/run.sh"
else
    echo -e "\n${YELLOW}Building Rust backend...${NC}"
    cargo build --release --locked --manifest-path "$INSTALL_DIR/backend-rust/Cargo.toml"
    EXEC_START="$INSTALL_DIR/backend-rust/target/release/lyrics-on-panel-backend"
fi

echo -e "\n${YELLOW}Setting up systemd service...${NC}"
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Lyrics-on-Panel MPRIS2 Backend ($BACKEND)
After=graphical-session.target

[Service]
Type=simple
ExecStart=$EXEC_START
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable "${SERVICE_NAME}.service"
systemctl --user restart "${SERVICE_NAME}.service"

echo -e "\n${GREEN}=== Installation Complete ===${NC}"
echo "Implementation: $BACKEND"
echo "Service: systemctl --user status ${SERVICE_NAME}"
echo "Logs:    journalctl --user -u ${SERVICE_NAME} -f"
echo "Backend: ws://127.0.0.1:23560"
