#!/bin/bash
# ── Docker Installation ──────────────────────────────────────────────
set -e

echo "=== Installing Docker ==="

# Default: assume Docker will work
export HAS_DOCKER=1

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
# (root can always use Docker, so skip the group check)
if [ "$(id -u)" = "0" ]; then
    USE_SUDO_DOCKER=0
elif groups "$USER" | grep -q docker; then
    USE_SUDO_DOCKER=0
else
    echo "Adding $USER to docker group..."
    sudo usermod -aG docker "$USER"
    echo ""
    echo "NOTE: You were added to the docker group. This takes effect on next login."
    echo "The installer will use sudo for docker commands in this session."
    echo ""
    USE_SUDO_DOCKER=1
fi

# ── Verify Docker can actually run ───────────────────────────────────
# On some container platforms (RunPod, etc.), Docker is installed but
# can't create networks due to missing kernel capabilities.
echo "Verifying Docker works..."
if [ "$USE_SUDO_DOCKER" = "1" ]; then
    DOCKER_CMD="sudo docker"
else
    DOCKER_CMD="docker"
fi

if $DOCKER_CMD info &>/dev/null 2>&1; then
    # Docker daemon is running — try starting it if not
    true
else
    # Try to start dockerd (containers won't have systemd)
    echo "Docker daemon not running, attempting to start..."
    dockerd &>/dev/null &
    DOCKERD_PID=$!
    sleep 3

    if ! $DOCKER_CMD info &>/dev/null 2>&1; then
        # dockerd failed to start (likely iptables/privilege issue)
        kill $DOCKERD_PID 2>/dev/null || true
        wait $DOCKERD_PID 2>/dev/null || true
        echo ""
        echo "Docker cannot run on this system (missing kernel capabilities)."
        echo "The app will be installed directly instead of using Docker containers."
        echo ""
        export HAS_DOCKER=0
    fi
fi

if [ "$HAS_DOCKER" = "1" ]; then
    echo "Docker is working."
else
    echo "Proceeding without Docker."
fi

echo ""
