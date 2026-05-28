#!/bin/bash
# ── Docker Installation ──────────────────────────────────────────────
set -e

echo "=== Installing Docker ==="

if command -v docker &>/dev/null; then
    echo "Docker is already installed: $(docker --version)"

    # Check for compose plugin
    if docker compose version &>/dev/null; then
        echo "Docker Compose plugin: $(docker compose version)"
    else
        echo "Installing Docker Compose plugin..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq docker-compose-plugin
    fi
else
    echo "Installing Docker..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg
    curl -fsSL https://get.docker.com | sudo sh

    echo "Installing Docker Compose plugin..."
    sudo apt-get install -y -qq docker-compose-plugin
fi

# Ensure the current user can use Docker without sudo
if ! groups "$USER" | grep -q docker; then
    echo "Adding $USER to docker group..."
    sudo usermod -aG docker "$USER"
    echo ""
    echo "NOTE: You were added to the docker group. This takes effect on next login."
    echo "The installer will use sudo for docker commands in this session."
    echo ""
    USE_SUDO_DOCKER=1
else
    USE_SUDO_DOCKER=0
fi

# Verify
if [ "$USE_SUDO_DOCKER" = "1" ]; then
    sudo docker info &>/dev/null && echo "Docker is working (via sudo)."
else
    docker info &>/dev/null && echo "Docker is working."
fi

echo ""
