# Open Image Generator

A self-hosted image generation app with a clean, Midjourney-style web interface. It wraps [ComfyUI](https://github.com/comfyanonymous/ComfyUI) behind a simple UI — type a prompt, get images. No node graphs, no workflow files, no fuss.

Built for small teams and personal use. Supports multiple users with accounts, quotas, and an admin dashboard.

## What You Get

- **Web UI** — clean prompt-based interface with image history, favorites, upscaling, and img2img
- **AI prompt enhancement** — an LLM rewrites your prompts for better results (powered by Ollama or LM Studio)
- **Three models** — Flux 2 Klein 9B (highest quality), Flux 2 Klein 4B (fast, open license), and Z-Image Turbo (fastest, open license)
- **Multi-user support** — registration, login, per-user quotas, model restrictions, and admin controls
- **Content safety** — text prompt screening and optional image upload screening via vision models
- **S3 storage** — optional S3-compatible image storage (AWS, Linode, R2, etc.) with signed URL serving
- **One-command install** — the installer handles everything on a fresh Linux machine

## Requirements

- **Linux** (Ubuntu 22.04+ recommended)
- **NVIDIA GPU** — Ampere or newer (RTX 3000/4000/5000 series, A100, etc.), including Blackwell GPUs
- **12 GB+ VRAM** recommended (8 GB works with smaller models)
- **32 GB+ System RAM** (32GB is the bare minimum to handle model offloads. 64GB or higher is ideal)
- **50 GB+ free disk space** (models are large)
- **sudo access**

The installer checks your GPU automatically and lets you know if it's compatible.

## Quick Start

```bash
git clone https://github.com/maloriedelilah/oig-installer.git
cd oig-installer
bash install.sh
```

Or as a one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/maloriedelilah/oig-installer/main/install.sh -o /tmp/oig-install.sh && bash /tmp/oig-install.sh
```

The installer works on two types of environments and auto-detects which path to take:

- **Bare metal / VPS** (Linode, Hetzner, etc.) — uses Docker for the app, systemd for GPU services. See [docs/BARE-METAL.md](docs/BARE-METAL.md).
- **GPU containers** (RunPod, etc.) — installs everything directly via supervisord, with optional Cloudflare Tunnel for HTTPS. See [docs/CONTAINER.md](docs/CONTAINER.md).

On a fresh install, the installer prompts for a few things: local vs production mode, an optional Hugging Face token for the Klein 9B model, and admin account credentials. On upgrades, it detects everything from the existing config and runs with zero prompts.

## Upgrading

An upgrade script is installed to `/opt/oig/upgrade.sh` during installation:

```bash
bash /opt/oig/upgrade.sh
```

This checks for a new version, backs up the database, saves the current release for rollback, and runs the installer. Old backups are automatically cleaned up (keeps the last 3).

To force a reinstall of the current version:

```bash
bash /opt/oig/upgrade.sh --force
```

## What Gets Installed

The installer sets up these components, adapting to the environment:

| Component | Purpose | Bare Metal | Container |
|----------------------|---------|------------|-----------|
| **App backend** | FastAPI API server | Docker | supervisord |
| **App frontend** | React web UI | Docker (Caddy) | Caddy + static build |
| **PostgreSQL** | User data, generations, settings | Docker | apt + supervisord |
| **Redis** | Rate limiting, caching | Docker | apt + supervisord |
| **Caddy** | Reverse proxy, static files | Docker (auto-SSL) | apt + supervisord (HTTP) |
| **Ollama** | LLM for prompt enhancement (qwen3:8b) + vision model (llava:7b) | systemd | supervisord |
| **ComfyUI** | Image generation backend | systemd | supervisord |
| **Cloudflare Tunnel** | HTTPS for containers (production only) | not needed | supervisord |

## Models

| Model | Size | Speed | License | Notes |
|-------|------|-------|---------|-------|
| Flux 2 Klein 9B | 9.6 GB | Slower | Non-commercial | Highest quality, requires HF token |
| Flux 2 Klein 4B | 7.8 GB | Medium | Apache 2.0 | Good at realism, can fail on body accuracy |
| Z-Image Turbo | 5.5 GB | Fastest | Apache 2.0 | Good balance of quality and speed |

### Adding the Klein 9B Model Later

If you skipped the Klein 9B model during installation:

1. Accept the license at [huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8](https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8)
2. Create a token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) — select "Read access to contents of all public gated repos you can access"
3. Download the model:
   ```bash
   wget --header="Authorization: Bearer YOUR_HF_TOKEN" \
     -O /opt/ComfyUI/models/diffusion_models/flux-2-klein-base-9b-fp8.safetensors \
     https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors
   ```
4. Restart ComfyUI: `sudo systemctl restart comfyui` (or `supervisorctl restart comfyui` on containers)

## Optional Features

These are configured through the admin UI after installation — no .env changes or restarts needed.

**S3 Image Storage** — Store generated images on S3-compatible storage (AWS, Linode Object Storage, Cloudflare R2, etc.) instead of locally on ComfyUI. Images are served via signed URLs. Configure under Admin > General > S3 Storage.

**Image Safety Screening** — Screen uploaded images (for img2img) using a vision model to detect prohibited content. Set a vision model (e.g. `llava:7b` for Ollama) under Admin > General > GPU Services > Vision Model.

**Email Notifications** — Email verification and password reset via Brevo. Configure under Admin > General > Email.

## Troubleshooting

**ComfyUI won't start or images fail to generate** — Check the logs (`sudo journalctl -u comfyui -f` or `tail -f /var/log/comfyui.log`). Common causes: out-of-VRAM errors (try a smaller model) or missing model files.

**Backend unavailable** — Services may still be starting. Wait a minute and refresh. Check backend logs: `docker compose logs -f backend` (bare metal) or `tail -f /var/log/oig-backend.log` (container).

**CUDA error on Blackwell GPUs** — The installer auto-detects Blackwell (sm_120+) and installs PyTorch with CUDA 12.8. If you see CUDA errors after manually updating PyTorch, reinstall custom node dependencies: `pip install --force-reinstall --no-cache-dir -r custom_nodes/*/requirements.txt`.

**GPU not detected** — Run `nvidia-smi` to verify drivers are installed. If not, install them first: [NVIDIA CUDA Installation Guide](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/).

## License

Open Image Generator is open source under the MIT License. Individual AI models have their own licenses — see the models table above.
