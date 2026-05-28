# Production Deployment Guide — Linode GPU VPS

## Architecture

```
Internet → Cloudflare (DNS) → Caddy (Docker, auto-SSL via ACME DNS) → {
  /api/*  → FastAPI backend (Docker)
  /*      → Static frontend (built into Caddy image)
}

Backend → ComfyUI (host, port 8188)
Backend → Ollama  (host, port 11434)
Backend → Postgres (Docker)
Backend → Redis (Docker)
```

Everything except ComfyUI and Ollama runs in Docker.
Caddy auto-provisions and renews SSL certs via Cloudflare DNS challenge.

## 1. Create a Deploy User (run as root)

Don't run everything as root. Create a dedicated user first:

```bash
apt update && apt upgrade -y

useradd -m -s /bin/bash deploy
usermod -aG sudo deploy
passwd deploy

# If you already set up SSH keys as root, copy them over
cp -r /root/.ssh /home/deploy/.ssh
chown -R deploy:deploy /home/deploy/.ssh

# Switch to the deploy user — everything below runs as deploy
su - deploy
```

## 2. Add Swap Space

The RTX 4000 ADA VPS has 15GB RAM — ComfyUI's VAE decode spills to system RAM
and will get OOM-killed without extra swap:

```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 3. Install Docker

```bash
sudo apt install docker-compose-plugin -y
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker deploy
# Log out and back in for the group to take effect
exit
su - deploy
```

No need to install Node.js — the frontend builds inside Docker.

## 4. Cloudflare API Token

In Cloudflare dashboard → My Profile → API Tokens → Create Token:

- Permissions: **Zone → DNS → Edit** AND **Zone → Zone → Read** (both required)
- Zone Resources: Include → your domain
- Save the token — you'll put it in `.env` as `CLOUDFLARE_API_TOKEN`

Point your domain's A record to the VPS IP in Cloudflare.
Set Cloudflare SSL/TLS mode to **Full (strict)**.

## 5. Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh

# Pull the model
ollama pull qwen3:8b

# Verify:
curl http://localhost:11434/v1/models
```

Ollama installs as a systemd service automatically. By default it only listens
on localhost — Docker containers can't reach it. Fix that:

```bash
sudo systemctl edit ollama
```

Add:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
```

Then `sudo systemctl daemon-reload && sudo systemctl restart ollama`.

## 6. Install ComfyUI

```bash
sudo apt install python3-venv python3-pip git -y

cd /opt
sudo git clone https://github.com/comfyanonymous/ComfyUI.git
sudo chown -R $USER:$USER /opt/ComfyUI
cd /opt/ComfyUI

python3 -m venv venv
source venv/bin/activate
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
pip install -r requirements.txt

# Download models into models/diffusion_models, models/text_encoders, models/vae
```

### Download models

Download each model directly on the VPS with `wget`. Note: the Flux 2 Klein 9B
model requires accepting a license on Hugging Face first — you'll need a
[Hugging Face token](https://huggingface.co/settings/tokens) with access granted
at the repo page.

**Diffusion models** → `models/diffusion_models/`

```bash
cd /opt/ComfyUI/models/diffusion_models

# Flux 2 Klein 9B (fp8, 9.6 GB) — requires HF token
# Accept license at: https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8
wget --header="Authorization: Bearer YOUR_HF_TOKEN" \
  https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9b-fp8/resolve/main/flux-2-klein-base-9b-fp8.safetensors

# Flux 2 Klein 4B (bf16, 7.8 GB) — Apache 2.0, no token needed
wget https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/resolve/main/flux-2-klein-4b.safetensors

# Z-Image Turbo (GGUF Q5_K_M, 5.5 GB)
wget https://huggingface.co/jayn7/Z-Image-Turbo-GGUF/resolve/main/z_image_turbo-Q5_K_M.gguf
```

**Text encoders** → `models/text_encoders/`

```bash
cd /opt/ComfyUI/models/text_encoders

# Qwen 3 8B fp8 (for Klein 9B, 8.7 GB)
wget https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors

# Qwen 3 4B (for Klein 4B and Z-Image Turbo, ~8 GB)
wget https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors
```

**VAE** → `models/vae/`

```bash
cd /opt/ComfyUI/models/vae

# Flux 2 small decoder (for Flux 2 Klein models, 335 MB)
wget -O full_encoder_small_decoder.safetensors \
  https://huggingface.co/black-forest-labs/FLUX.2-small-decoder/resolve/main/full_encoder_small_decoder.safetensors

# ae.safetensors (for Z-Image Turbo, 335 MB)
wget https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors
```

**Upscale models** → `models/upscale_models/`

```bash
cd /opt/ComfyUI/models/upscale_models

# 4x UltraSharp (ESRGAN, 64 MB)
wget https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth
```

### Install custom nodes

Clone the two required custom node repos directly on the VPS:

```bash
cd /opt/ComfyUI/custom_nodes
git clone https://github.com/city96/ComfyUI-GGUF.git
git clone https://github.com/glibsonoran/Plush-for-ComfyUI.git
```

Then install their Python dependencies:

```bash
cd /opt/ComfyUI
source venv/bin/activate

for req in custom_nodes/*/requirements.txt; do
  echo "Installing deps for $(dirname $req)..."
  pip install -r "$req" 2>/dev/null
done
```

### ComfyUI systemd service

Create `/etc/systemd/system/comfyui.service`:

```ini
[Unit]
Description=ComfyUI
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/opt/ComfyUI
ExecStart=/opt/ComfyUI/venv/bin/python main.py --listen 0.0.0.0 --port 8188 --preview-method latent2rgb
Restart=on-failure
RestartSec=10
Environment=CUDA_VISIBLE_DEVICES=0

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable comfyui
sudo systemctl start comfyui

# Verify:
curl http://localhost:8188/queue
```

## 7. Deploy the App

```bash
sudo mkdir -p /opt/oig
sudo chown deploy:deploy /opt/oig

git clone YOUR_REPO_URL /opt/oig
cd /opt/oig

# Create production .env
cp .env.production.example .env
nano .env  # fill in all values (see comments in the file)

# Generate a JWT secret:
openssl rand -hex 32

# Update the domain in Caddyfile
nano Caddyfile  # replace yourdomain.com

# Deploy
chmod +x deploy.sh
./deploy.sh
```

That's it. Docker builds everything — backend, frontend, Caddy with the
Cloudflare plugin — and Caddy auto-provisions the SSL cert on first boot.

## 8. Verify

```bash
# Docker services
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs caddy --tail 20
docker compose -f docker-compose.prod.yml logs backend --tail 20

# SSL cert (should show your domain)
curl -I https://yourdomain.com

# GPU services
curl http://localhost:8188/queue
curl http://localhost:11434/v1/models
```

## Updating

```bash
cd /opt/oig
git pull
./deploy.sh
```

## Useful Commands

```bash
# Logs
docker compose -f docker-compose.prod.yml logs -f backend
docker compose -f docker-compose.prod.yml logs -f caddy
sudo journalctl -u comfyui -f
sudo journalctl -u ollama -f

# Restart
docker compose -f docker-compose.prod.yml restart backend
docker compose -f docker-compose.prod.yml up -d --build caddy  # rebuild frontend
sudo systemctl restart comfyui
sudo systemctl restart ollama

# Database backup
docker compose -f docker-compose.prod.yml exec db pg_dump -U oig open_image_gen > backup_$(date +%Y%m%d).sql

# Database restore
cat backup.sql | docker compose -f docker-compose.prod.yml exec -T db psql -U oig open_image_gen
```

## Docker → Host Networking

The backend reaches ComfyUI and Ollama on the host via `host.docker.internal`,
mapped by `extra_hosts` in docker-compose.prod.yml. The default URLs in
`.env.production.example` already use this.
