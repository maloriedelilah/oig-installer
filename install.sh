#!/bin/bash
# ── Open Image Generator — One-Command Installer ────────────────────
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/maloriedelilah/oig-installer/main/install.sh | bash
#   — or —
#   git clone https://github.com/maloriedelilah/oig-installer.git && cd oig-installer && bash install.sh
#
# Installs everything needed to run OIG on a fresh Linux box:
#   1. Checks for an Ampere+ NVIDIA GPU
#   2. Installs Docker + Docker Compose
#   3. Installs Ollama + pulls qwen3:8b
#   4. Installs ComfyUI + custom nodes + downloads all models
#   5. Downloads the app release, configures .env, builds and starts Docker
#
# Supports two modes:
#   local       — HTTP only, no domain/SSL required (default)
#   production  — HTTPS via Caddy + Cloudflare DNS
#
set -e

# ── Colours ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

# ── GitHub coordinates ───────────────────────────────────────────────
# Change these to your GitHub org/user and repo names.
INSTALLER_REPO="maloriedelilah/oig-installer"
INSTALLER_BRANCH="main"

banner() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║           Open Image Generator — Installer              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

step() {
    echo ""
    echo -e "${GREEN}${BOLD}[$1/5]${NC} ${BOLD}$2${NC}"
    echo -e "${GREEN}────────────────────────────────────────────────${NC}"
}

fail() {
    echo -e "${RED}ERROR:${NC} $1"
    exit 1
}

banner

# ── Pre-flight checks ───────────────────────────────────────────────
if [ "$(uname)" != "Linux" ]; then
    fail "This installer only supports Linux."
fi

# Ensure $USER is set (empty on some minimal installs / root shells)
if [ -z "$USER" ]; then
    USER=$(whoami)
    export USER
fi

if ! sudo -v 2>/dev/null; then
    fail "This installer requires sudo access."
fi

# Detect init system — systemd on normal servers, supervisord on containers
export HAS_SYSTEMD=0
if pidof systemd &>/dev/null && command -v systemctl &>/dev/null; then
    export HAS_SYSTEMD=1
fi

# ── Determine script directory ───────────────────────────────────────
# If run from inside the cloned installer repo, use local scripts.
# If run standalone (curl | bash), clone the installer repo first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/opt/oig"

if [ -f "$SCRIPT_DIR/scripts/install/check-gpu.sh" ]; then
    INSTALL_SCRIPTS="$SCRIPT_DIR/scripts/install"
    # Read VERSION from the local repo
    if [ -f "$SCRIPT_DIR/VERSION" ]; then
        OIG_VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')
    else
        fail "VERSION file not found. Your installer repo may be incomplete."
    fi
else
    # Running standalone — clone the installer repo to get scripts + VERSION
    echo "Fetching installer scripts..."
    TMP_CLONE_DIR=$(mktemp -d)
    git clone --depth 1 -b "$INSTALLER_BRANCH" "https://github.com/$INSTALLER_REPO.git" "$TMP_CLONE_DIR/installer"
    INSTALL_SCRIPTS="$TMP_CLONE_DIR/installer/scripts/install"
    SCRIPT_DIR="$TMP_CLONE_DIR/installer"
    OIG_VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')
fi

chmod +x "$INSTALL_SCRIPTS"/*.sh

echo -e "OIG version: ${BOLD}v${OIG_VERSION}${NC}"

# Build the download URL for the app tarball
OIG_TARBALL_URL="https://github.com/$INSTALLER_REPO/releases/download/v${OIG_VERSION}/oig-v${OIG_VERSION}.tar.gz"
export OIG_TARBALL_URL
export OIG_VERSION

# ── Choose install mode ──────────────────────────────────────────────
echo ""
echo "How would you like to deploy?"
echo ""
echo "  1) Local mode   — HTTP only at http://localhost (no domain needed)"
echo "  2) Production   — HTTPS with your own domain via Cloudflare"
echo ""
read -p "Choose [1]: " MODE_CHOICE
MODE_CHOICE="${MODE_CHOICE:-1}"

if [ "$MODE_CHOICE" = "2" ]; then
    export INSTALL_MODE="production"
    echo ""
    echo -e "Mode: ${BOLD}Production${NC}"
else
    export INSTALL_MODE="local"
    echo ""
    echo -e "Mode: ${BOLD}Local${NC}"
fi

# ── Optional: Hugging Face token for Klein 9B ────────────────────────
echo ""
echo "The Flux 2 Klein 9B model requires a Hugging Face token (non-commercial license)."
echo "Klein 4B and Z-Image Turbo are available without one."
echo ""
read -p "Hugging Face token (press Enter to skip): " HF_INPUT
export HF_TOKEN="${HF_INPUT:-}"

if [ -n "$HF_TOKEN" ]; then
    echo -e "Klein 9B: ${GREEN}will be downloaded${NC}"
else
    echo -e "Klein 9B: ${YELLOW}skipped${NC} (you can add it later)"
fi

# ═══════════════════════════════════════════════════════════════════
# Step 1: GPU Check
# ═══════════════════════════════════════════════════════════════════
step 1 "Checking GPU"
source "$INSTALL_SCRIPTS/check-gpu.sh"

# ═══════════════════════════════════════════════════════════════════
# Step 2: Docker
# ═══════════════════════════════════════════════════════════════════
step 2 "Installing Docker"
source "$INSTALL_SCRIPTS/install-docker.sh"

# ═══════════════════════════════════════════════════════════════════
# Step 3: Ollama
# ═══════════════════════════════════════════════════════════════════
step 3 "Installing Ollama + LLM"
source "$INSTALL_SCRIPTS/install-ollama.sh"

# ═══════════════════════════════════════════════════════════════════
# Step 4: ComfyUI
# ═══════════════════════════════════════════════════════════════════
step 4 "Installing ComfyUI + Models"
source "$INSTALL_SCRIPTS/install-comfyui.sh"

# ═══════════════════════════════════════════════════════════════════
# Step 5: App Setup
# ═══════════════════════════════════════════════════════════════════
step 5 "Setting up Open Image Generator"
source "$INSTALL_SCRIPTS/setup-app.sh"

# ═══════════════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║              Installation Complete!                      ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$INSTALL_MODE" = "local" ]; then
    echo -e "  Open your browser to:  ${BOLD}http://localhost${NC}"
else
    echo -e "  Open your browser to:  ${BOLD}https://$DOMAIN${NC}"
    echo "  (DNS may take a few minutes to propagate)"
fi

echo ""
echo -e "  Version: ${BOLD}v${OIG_VERSION}${NC}"
echo ""
if [ "$HAS_SYSTEMD" = "1" ]; then
    SVCMGR="systemd"
else
    SVCMGR="supervisord"
fi
echo "  Services:"
echo "    App          → Docker (port 80)"
echo "    ComfyUI      → $SVCMGR (port 8188)"
echo "    Ollama       → $SVCMGR (port 11434)"
echo ""
echo "  Useful commands:"
echo "    cd $APP_DIR"
echo "    docker compose logs -f            # app logs"
if [ "$HAS_SYSTEMD" = "1" ]; then
    echo "    sudo journalctl -u comfyui -f     # ComfyUI logs"
    echo "    sudo journalctl -u ollama -f      # Ollama logs"
    echo "    sudo systemctl restart comfyui    # restart ComfyUI"
else
    echo "    tail -f /var/log/comfyui.log      # ComfyUI logs"
    echo "    tail -f /var/log/ollama.log       # Ollama logs"
    echo "    supervisorctl restart comfyui     # restart ComfyUI"
fi
echo ""

# Clean up temp clone if we made one
if [ -n "$TMP_CLONE_DIR" ] && [ -d "$TMP_CLONE_DIR" ]; then
    rm -rf "$TMP_CLONE_DIR"
fi
