#!/bin/bash
# ── ComfyUI Installation ─────────────────────────────────────────────
# Installs ComfyUI, custom nodes, downloads models, creates systemd service.
set -e

COMFY_DIR="/opt/ComfyUI"
HF_TOKEN="${HF_TOKEN:-}"

echo "=== Installing ComfyUI ==="

# Prerequisites
echo "Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq python3-venv python3-pip git wget

# Clone ComfyUI
if [ -d "$COMFY_DIR" ]; then
    echo "ComfyUI directory already exists at $COMFY_DIR"
    echo "Pulling latest changes..."
    cd "$COMFY_DIR"
    git pull --ff-only 2>/dev/null || echo "  (already up to date or detached)"
else
    echo "Cloning ComfyUI..."
    sudo git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
    sudo chown -R "$USER:$USER" "$COMFY_DIR"
fi

cd "$COMFY_DIR"

# Create virtual environment
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

# Install PyTorch with CUDA support
# Detect GPU compute capability to pick the right PyTorch build
GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '[:space:]')
GPU_CC_MAJOR=$(echo "$GPU_CC" | cut -d. -f1)

if [ "$GPU_CC_MAJOR" -ge 10 ] 2>/dev/null; then
    # Blackwell (sm_120) and newer need CUDA 12.8+
    echo "Detected compute capability $GPU_CC (Blackwell+) — installing PyTorch with CUDA 12.8..."
    echo "(this may take a few minutes)"
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
else
    echo "Installing PyTorch (CUDA 12.4)..."
    echo "(this may take a few minutes)"
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
fi

echo "Installing ComfyUI requirements..."
pip install --quiet -r requirements.txt

# ── Custom Nodes ──────────────────────────────────────────────────────
echo ""
echo "Installing custom nodes..."

cd "$COMFY_DIR/custom_nodes"

if [ ! -d "ComfyUI-GGUF" ]; then
    echo "  Cloning ComfyUI-GGUF..."
    git clone https://github.com/city96/ComfyUI-GGUF.git
else
    echo "  ComfyUI-GGUF already installed."
fi

if [ ! -d "Plush-for-ComfyUI" ]; then
    echo "  Cloning Plush-for-ComfyUI..."
    git clone https://github.com/glibsonoran/Plush-for-ComfyUI.git
else
    echo "  Plush-for-ComfyUI already installed."
fi

if [ ! -d "Comfyui-DiffusersUtils" ]; then
    echo "  Cloning Comfyui-DiffusersUtils (GLM-Image support)..."
    git clone https://github.com/lrzjason/Comfyui-DiffusersUtils.git
else
    echo "  Comfyui-DiffusersUtils already installed."
fi

if [ ! -d "ComfyUI-KJNodes" ]; then
    echo "  Cloning ComfyUI-KJNodes (outpainting support)..."
    git clone https://github.com/kijai/ComfyUI-KJNodes.git
else
    echo "  ComfyUI-KJNodes already installed."
fi

if [ ! -d "ComfyUI-LTXVideo" ]; then
    echo "  Cloning ComfyUI-LTXVideo (video generation support)..."
    git clone https://github.com/Lightricks/ComfyUI-LTXVideo.git
else
    echo "  ComfyUI-LTXVideo already installed."
fi
# LTXVideo requires newer kornia than what ships with ComfyUI
pip install --quiet --upgrade kornia opencv-python 2>/dev/null || true
# Fix kornia missing 'pad' export in pyramid module (upstream bug)
PYRAMID_BLEND="$COMFY_DIR/custom_nodes/ComfyUI-LTXVideo/pyramid_blending.py"
if [ -f "$PYRAMID_BLEND" ] && grep -q "from kornia.*import.*pad" "$PYRAMID_BLEND"; then
    echo "  Patching LTXVideo kornia compatibility..."
    sed -i 's/    pad,//' "$PYRAMID_BLEND"
    sed -i '/from torch import Tensor/a\pad = F.pad' "$PYRAMID_BLEND"
fi

# OIG custom nodes (shipped with the app, not cloned from git)
if [ -d "/opt/oig/comfy-nodes/oig-nodes" ]; then
    echo "  Installing OIG custom nodes..."
    cp -r /opt/oig/comfy-nodes/oig-nodes "$COMFY_DIR/custom_nodes/oig-nodes"
else
    echo "  OIG custom nodes not found (will be installed on next upgrade)."
fi

# Install custom node dependencies
cd "$COMFY_DIR"
source venv/bin/activate
for req in custom_nodes/*/requirements.txt; do
    if [ -f "$req" ]; then
        echo "  Installing deps for $(dirname "$req")..."
        pip install --quiet -r "$req" 2>/dev/null || true
    fi
done

# DiffusersUtils requires bleeding-edge transformers/diffusers/peft from git
echo "  Installing DiffusersUtils extra deps (transformers, diffusers, peft)..."
pip install --quiet git+https://github.com/huggingface/transformers.git 2>/dev/null || true
pip install --quiet git+https://github.com/huggingface/diffusers.git 2>/dev/null || true
pip install --quiet git+https://github.com/huggingface/peft.git 2>/dev/null || true
pip install --quiet huggingface-hub 2>/dev/null || true
pip install --quiet bitsandbytes 2>/dev/null || true

# ── Download Models ───────────────────────────────────────────────────
echo ""
echo "Downloading models (this will take a while)..."

download() {
    local url="$1"
    local dest="$2"
    local label="$3"
    local auth="$4"

    # Skip if file exists and is non-empty
    if [ -f "$dest" ] && [ -s "$dest" ]; then
        echo "  [skip] $label (already exists)"
        return
    fi

    # Clean up any 0-byte leftover from a previous failed download
    rm -f "$dest"

    echo "  [downloading] $label..."
    mkdir -p "$(dirname "$dest")"
    if [ -n "$auth" ]; then
        wget --quiet --show-progress --header="Authorization: Bearer $auth" -O "$dest" "$url" || true
    else
        wget --quiet --show-progress -O "$dest" "$url" || true
    fi

    # Verify the download actually produced a file
    if [ ! -s "$dest" ]; then
        rm -f "$dest"
        echo "  [FAILED] $label — download failed or file is empty"
        if [ -n "$auth" ]; then
            # Extract the model page URL from the download URL
            local model_page
            model_page=$(echo "$url" | sed 's|/resolve/main/.*||')
            echo ""
            echo "           Possible causes:"
            echo "             • You haven't accepted the model license yet"
            echo "             • Your Hugging Face token is invalid or expired"
            echo ""
            echo "           To fix:"
            echo "             1. Accept the license: $model_page"
            echo "             2. Check your token:   https://huggingface.co/settings/tokens"
            echo "             3. Re-run the installer — it will skip models already downloaded"
            echo ""
        fi
    fi
}

# Diffusion models
download \
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/resolve/main/flux-2-klein-4b.safetensors" \
    "$COMFY_DIR/models/diffusion_models/flux-2-klein-4b.safetensors" \
    "Flux 2 Klein 4B (7.8 GB)"

download \
    "https://huggingface.co/jayn7/Z-Image-Turbo-GGUF/resolve/main/z_image_turbo-Q5_K_M.gguf" \
    "$COMFY_DIR/models/diffusion_models/z_image_turbo-Q5_K_M.gguf" \
    "Z-Image Turbo GGUF (5.5 GB)"

# Klein 9B requires HF token (non-commercial license)
if [ -n "$HF_TOKEN" ]; then
    download \
        "https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors" \
        "$COMFY_DIR/models/diffusion_models/flux-2-klein-base-9b-fp8.safetensors" \
        "Flux 2 Klein 9B fp8 (9.6 GB, non-commercial)" \
        "$HF_TOKEN"
else
    echo ""
    echo "  [skip] Flux 2 Klein 9B — requires a Hugging Face token."
    echo "         Accept the license at: https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8"
    echo "         Then re-run with: HF_TOKEN=hf_xxx bash scripts/install/install-comfyui.sh"
    echo "         (Klein 4B and Z-Image Turbo are available without a token)"
    echo ""
fi

# Text encoders
download \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
    "$COMFY_DIR/models/text_encoders/qwen_3_4b.safetensors" \
    "Qwen 3 4B text encoder (8 GB)"

download \
    "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
    "$COMFY_DIR/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
    "Qwen 3 8B fp8 text encoder (8.7 GB)"

# VAE
download \
    "https://huggingface.co/black-forest-labs/FLUX.2-small-decoder/resolve/main/full_encoder_small_decoder.safetensors" \
    "$COMFY_DIR/models/vae/full_encoder_small_decoder.safetensors" \
    "Flux 2 VAE small decoder (335 MB)"

download \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" \
    "$COMFY_DIR/models/vae/ae.safetensors" \
    "Z-Image VAE (335 MB)"

# Upscale models
download \
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth" \
    "$COMFY_DIR/models/upscale_models/4x-UltraSharp.pth" \
    "4x UltraSharp upscaler (64 MB)"

deactivate

# ── Service Setup ────────────────────────────────────────────────────
echo ""
HAS_SYSTEMD="${HAS_SYSTEMD:-0}"

if [ "$HAS_SYSTEMD" = "1" ]; then
    # ── systemd (normal Linux servers) ───────────────────────────────
    echo "Creating ComfyUI systemd service..."

    cat <<EOF | sudo tee /etc/systemd/system/comfyui.service >/dev/null
[Unit]
Description=ComfyUI
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$COMFY_DIR
ExecStart=$COMFY_DIR/venv/bin/python main.py --listen 0.0.0.0 --port 8188 --preview-method latent2rgb
Restart=on-failure
RestartSec=10
Environment=CUDA_VISIBLE_DEVICES=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable comfyui
    sudo systemctl start comfyui
else
    # ── supervisord (RunPod, containers) ─────────────────────────────
    echo "Creating ComfyUI supervisor config..."

    # Ensure supervisor is running (Ollama script installs it)
    if ! pgrep -x supervisord &>/dev/null; then
        supervisord -c /etc/supervisor/supervisord.conf 2>/dev/null || true
    fi

    mkdir -p /etc/supervisor/conf.d
    cat > /etc/supervisor/conf.d/comfyui.conf <<EOF
[program:comfyui]
command=$COMFY_DIR/venv/bin/python main.py --listen 0.0.0.0 --port 8188 --preview-method latent2rgb
directory=$COMFY_DIR
user=$USER
environment=CUDA_VISIBLE_DEVICES="0"
autostart=true
autorestart=true
startsecs=10
startretries=3
stdout_logfile=/var/log/comfyui.log
stderr_logfile=/var/log/comfyui.log
EOF

    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true
    supervisorctl start comfyui 2>/dev/null || true
fi

# Wait for ComfyUI to be ready
echo "Waiting for ComfyUI to start (loading models, may take a minute)..."
for _ in {1..120}; do
    if curl -sf http://localhost:8188/queue &>/dev/null; then
        echo "ComfyUI is ready."
        break
    fi
    sleep 2
done

if ! curl -sf http://localhost:8188/queue &>/dev/null; then
    echo "WARNING: ComfyUI hasn't responded yet. It may still be loading models."
    if [ "$HAS_SYSTEMD" = "1" ]; then
        echo "Check: sudo journalctl -u comfyui -f"
    else
        echo "Check: tail -f /var/log/comfyui.log"
    fi
fi

echo ""
