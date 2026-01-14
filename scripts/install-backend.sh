#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO_URL="https://github.com/KangweiZhu/lyrics-on-panel"
INSTALL_DIR="$HOME/.local/share/lyrics-on-panel"
SERVICE_NAME="Universal-Mpris-LyricServer"

echo -e "${GREEN}=== Lyrics-on-Panel Backend Installer ===${NC}"

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run as root${NC}"
    exit 1
fi

# Step 1: Install build dependencies for dbus-python
# Todo: Debian / Nix / SUSE support
echo -e "\n${YELLOW}[1/5] Installing system build dependencies...${NC}"
sudo pacman -S --needed --noconfirm git curl dbus glib2 pkgconf base-devel

# Step 2: Install uv
echo -e "\n${YELLOW}[2/5] Setting up uv...${NC}"
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
echo -e "${GREEN}uv: $(uv --version)${NC}"

# Step 3: Clone/update repository
echo -e "\n${YELLOW}[3/5] Cloning project...${NC}"
rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"

# Step 4: Create venv with Python 3.13 and install dependencies
echo -e "\n${YELLOW}[4/5] Creating Python environment...${NC}"
mkdir -p "$INSTALL_DIR/backend"
cd "$INSTALL_DIR/backend"

uv self update
uv venv --python 3.13.11
uv pip install websockets==15.0.1 dbus-python==1.4.0

# Create launcher
cat > "$INSTALL_DIR/backend/run.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source .venv/bin/activate
exec python src/server.py
EOF
chmod +x "$INSTALL_DIR/backend/run.sh"

# Step 5: Setup systemd service
echo -e "\n${YELLOW}[5/5] Setting up systemd service...${NC}"
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Lyrics-on-Panel MPRIS2 Backend
After=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/backend/run.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}.service"

echo -e "\n${GREEN}=== Installation Complete ===${NC}"
echo "Service: systemctl --user status ${SERVICE_NAME}"
echo "Logs:    journalctl --user -u ${SERVICE_NAME} -f"
echo "Backend: ws://127.0.0.1:23560"
