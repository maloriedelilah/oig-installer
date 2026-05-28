#!/bin/bash
# ── Open Image Generator — One-Command Installer ────────────────────
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/open-image-generator/main/install.sh | bash
#   — or —
#   git clone <repo> && cd open-image-generator && bash install.sh
#
# Installs everything needed to run OIG on a fresh Linux box:
#   1. Checks for an Ampere+ NVIDIA GPU
#   2. Installs Docker + Docker Compose
#   3. Installs Ollama + pulls qwen3:8b
#   4. Installs ComfyUI + custom nodes + downloads all models
#   5. Clones the app, configures .env, builds and starts the Docker stack
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

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

fail() {
    echo -e "${RED}ERROR:${NC} $1"
    exit 1
}

banner

# ── Pre-flight checks ───────────────────────────────────────────────
# Must be Linux
if [ "$(uname)" != "Linux" ]; then
    fail "This installer only supports Linux."
fi

# Need sudo
if ! sudo -v 2>/dev/null; then
    fail "This installer requires sudo access."
fi

# ── Determine script directory ───────────────────────────────────────
# If run from inside the repo, use local scripts.
# If run standalone (curl | bash), we'll clone the repo first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${REPO_URL:-https://github.com/YOUR_USERNAME/open-image-generator.git}"
APP_DIR="/opt/oig"

# Check if sub-scripts exist locally (i.e. we're inside the cloned repo)
if [ -f "$SCRIPT_DIR/scripts/install/check-gpu.sh" ]; then
    INSTALL_SCRIPTS="$SCRIPT_DIR/scripts/install"
else
    # Running standalone — clone the repo first to get the scripts
    echo "Cloning repository to get installer scripts..."
    TMP_CLONE_DIR=$(mktemp -d)
    git clone --depth 1 "$REPO_URL" "$TMP_CLONE_DIR/oig"
    INSTALL_SCRIPTS="$TMP_CLONE_DIR/oig/scripts/install"
    SCRIPT_DIR="$TMP_CLONE_DIR/oig"
fi

# Make all sub-scripts executable
chmod +x "$INSTALL_SCRIPTS"/*.sh

# ── Choose install mode ──────────────────────────────────────────────
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

# Export variables that sub-scripts need
export INSTALL_MODE
export HF_TOKEN
export REPO_URL

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
echo "  Services:"
echo "    App          → Docker (port 80)"
echo "    ComfyUI      → systemd (port 8188)"
echo "    Ollama       → systemd (port 11434)"
echo ""
echo "  Useful commands:"
echo "    cd $APP_DIR"
echo "    docker compose logs -f            # app logs"
echo "    sudo journalctl -u comfyui -f     # ComfyUI logs"
echo "    sudo journalctl -u ollama -f      # Ollama logs"
echo "    sudo systemctl restart comfyui    # restart ComfyUI"
echo ""

# Clean up temp clone if we made one
if [ -n "$TMP_CLONE_DIR" ] && [ -d "$TMP_CLONE_DIR" ]; then
    rm -rf "$TMP_CLONE_DIR"
fi
