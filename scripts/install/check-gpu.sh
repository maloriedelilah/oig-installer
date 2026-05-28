#!/bin/bash
# ── GPU Detection ────────────────────────────────────────────────────
# Verifies an NVIDIA Ampere or newer GPU is present.
# Ampere = compute capability 8.x, Ada Lovelace = 8.9, Hopper = 9.x, Blackwell = 10.x
set -e

echo "Checking for NVIDIA GPU..."

if ! command -v nvidia-smi &>/dev/null; then
    echo ""
    echo "ERROR: nvidia-smi not found."
    echo "Please install NVIDIA drivers first:"
    echo "  https://docs.nvidia.com/cuda/cuda-installation-guide-linux/"
    exit 1
fi

# Get GPU name and compute capability
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | xargs)
if [ -z "$GPU_NAME" ]; then
    echo "ERROR: No NVIDIA GPU detected."
    exit 1
fi

echo "Found GPU: $GPU_NAME"

# Check compute capability via nvidia-smi
# compute_cap format is "8.6" or "8.9" etc.
COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | xargs)

if [ -z "$COMPUTE_CAP" ]; then
    # Older nvidia-smi versions don't have compute_cap — fall back to name matching
    echo "WARNING: Could not determine compute capability directly."
    echo "Checking GPU name against known architectures..."

    # Known pre-Ampere patterns to reject
    if echo "$GPU_NAME" | grep -qiE "GTX (9|10|16)|RTX 20|Tesla [KVMPST]|Quadro.*(P|GP|GV|M)|Titan (V|Xp|X |RTX)"; then
        echo ""
        echo "ERROR: $GPU_NAME appears to be pre-Ampere (requires Ampere or newer)."
        echo "Supported GPUs: RTX 30xx, RTX 40xx, RTX 50xx, A100, A6000, L40, H100, etc."
        exit 1
    fi
    echo "GPU name looks compatible. Proceeding..."
else
    MAJOR=$(echo "$COMPUTE_CAP" | cut -d. -f1)
    echo "Compute capability: $COMPUTE_CAP"

    if [ "$MAJOR" -lt 8 ]; then
        echo ""
        echo "ERROR: $GPU_NAME has compute capability $COMPUTE_CAP (pre-Ampere)."
        echo "This project requires Ampere or newer (compute capability 8.0+)."
        echo "Supported GPUs: RTX 30xx, RTX 40xx, RTX 50xx, A100, A6000, L40, H100, etc."
        exit 1
    fi

    echo "GPU is Ampere or newer — good to go."
fi

# Check VRAM
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | xargs)
VRAM_GB=$((VRAM_MB / 1024))
echo "VRAM: ${VRAM_GB}GB"

if [ "$VRAM_GB" -lt 12 ]; then
    echo ""
    echo "WARNING: Only ${VRAM_GB}GB VRAM detected. The Flux 2 Klein 9B model"
    echo "needs ~12GB VRAM. You may be limited to smaller models (Klein 4B, Z-Image Turbo)."
    echo ""
    read -p "Continue anyway? [y/N] " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
