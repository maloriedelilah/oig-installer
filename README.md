# Open Image Generator

A self-hosted image generation app with a clean, Midjourney-style web interface. It wraps [ComfyUI](https://github.com/comfyanonymous/ComfyUI) behind a simple UI — type a prompt, get images. No node graphs, no workflow files, no fuss.

Built for small teams and personal use. Supports multiple users with accounts, quotas, and an admin dashboard.

## What You Get

- **Web UI** — clean prompt-based interface with image history, favorites, upscaling, and img2img
- **AI prompt enhancement** — an LLM rewrites your prompts for better results (powered by Ollama)
- **Three Flux 2 models** — Klein 9B (highest quality), Klein 4B (fast, open license), and Z-Image Turbo (fastest)
- **Multi-user support** — registration, login, per-user quotas, model restrictions, and admin controls
- **One-command install** — the installer sets up everything on a fresh Linux server

## Requirements

- **Linux** (Ubuntu 22.04+ recommended)
- **NVIDIA GPU** — Ampere generation or newer (RTX 3000 series, RTX 4000 series, RTX 5000 series, A100, etc.)
- **12 GB+ VRAM** recommended (8 GB works with smaller models)
- **50 GB+ free disk space** (models are large)
- **sudo access**

The installer will check your GPU automatically and let you know if it's compatible.

## Quick Start

Clone this repo and run the installer:

```bash
git clone https://github.com/maloriedelilah/oig-installer.git
cd oig-installer
bash install.sh
```

Or as a one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/maloriedelilah/oig-installer/main/install.sh | bash
```

The installer will walk you through a few prompts:

1. **Local or Production** — local mode runs on `http://localhost` with no domain needed. Production mode sets up HTTPS with your own domain via Cloudflare.
2. **Hugging Face token** (optional) — needed for the Flux 2 Klein 9B model, which has a non-commercial license. The other two models don't require one.
3. **Admin account** — email, username, and password for your first admin user.

The whole process takes about 10–20 minutes depending on your internet speed (the models are several GB each).

## What Gets Installed

The installer sets up five components:

| Component | Purpose | Location |
|-----------|---------|----------|
| **Docker** | Runs the web app, database, and reverse proxy | system service |
| **Ollama** | Hosts the LLM for prompt enhancement (qwen3:8b) | systemd service, port 11434 |
| **ComfyUI** | The image generation backend | `/opt/ComfyUI`, systemd service, port 8188 |
| **PostgreSQL** | Stores users, generations, and settings | Docker container |
| **Caddy** | Web server / reverse proxy | Docker container, port 80 (or 443 in production) |

## After Installation

Once the installer finishes, open your browser to `http://localhost` (or your domain in production mode).

Log in with the admin credentials you set during installation. From there you can create accounts for other users, adjust quotas, and configure settings from the admin panel.

### Useful Commands

```bash
# View app logs
cd /opt/oig && docker compose logs -f

# View ComfyUI logs
sudo journalctl -u comfyui -f

# View Ollama logs
sudo journalctl -u ollama -f

# Restart ComfyUI (e.g. after adding models)
sudo systemctl restart comfyui

# Rebuild and restart the app (e.g. after an upgrade)
cd /opt/oig && docker compose up -d --build
```

### Upgrading

To upgrade to a newer version, re-run the installer. It will download the latest release and rebuild the Docker containers while keeping your database and configuration intact.

```bash
cd oig-installer
git pull
bash install.sh
```

### Adding the Klein 9B Model Later

If you skipped the Klein 9B model during installation, you can add it anytime:

1. Accept the license at [huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8](https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8)
2. Download the model:
   ```bash
   wget --header="Authorization: Bearer YOUR_HF_TOKEN" \
     -O /opt/ComfyUI/models/diffusion_models/flux-2-klein-base-9b-fp8.safetensors \
     https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors
   ```
3. Restart ComfyUI: `sudo systemctl restart comfyui`

## Models

| Model | Size | Speed | License | Notes |
|-------|------|-------|---------|-------|
| Flux 2 Klein 9B | 9.6 GB | Slower | Non-commercial | Highest quality, requires HF token |
| Flux 2 Klein 4B | 7.8 GB | Medium | Apache 2.0 | Good balance of quality and speed |
| Z-Image Turbo | 5.5 GB | Fastest | Apache 2.0 | Great for quick iterations |

## Troubleshooting

**ComfyUI won't start or images fail to generate**
Check the logs: `sudo journalctl -u comfyui -f`. Common causes are out-of-VRAM errors (try a smaller model) or missing model files.

**The web UI loads but shows "backend unavailable"**
The Docker containers may still be starting. Wait a minute and refresh. Check logs with `cd /opt/oig && docker compose logs -f backend`.

**Ollama is slow or unresponsive**
The qwen3:8b model needs a few GB of RAM. If your server is tight on memory, the 8 GB swap the installer creates should help, but very low-RAM systems may struggle.

**GPU not detected**
Make sure NVIDIA drivers are installed: `nvidia-smi` should show your GPU. If not, install drivers first: [NVIDIA CUDA Installation Guide](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/).

## License

Open Image Generator is open source. The app itself is available under the MIT License. Individual AI models have their own licenses — see the models table above.
