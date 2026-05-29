# Bare Metal / VPS Deployment

This guide covers deploying OIG on a standard Linux server — Linode GPU, Hetzner, a home server, or any machine where you have root access and Docker works normally.

## Architecture

```
Internet → Cloudflare (DNS + SSL) → Caddy (Docker, port 80/443) → {
  /api/*  → FastAPI backend (Docker)
  /*      → Static frontend (Docker)
}

Backend → ComfyUI (host, port 8188)
Backend → Ollama  (host, port 11434)
Backend → PostgreSQL (Docker)
Backend → Redis (Docker)
```

The web app, database, and Redis run in Docker containers. ComfyUI and Ollama run directly on the host via systemd so they have native GPU access. Caddy handles SSL automatically via Cloudflare DNS challenge (production mode) or serves plain HTTP (local mode).

## Installation

```bash
git clone https://github.com/maloriedelilah/oig-installer.git
cd oig-installer
bash install.sh
```

The installer prompts for:

1. **Local or Production** — local mode serves `http://localhost`. Production mode sets up HTTPS with your own domain via Cloudflare.
2. **Hugging Face token** (optional) — needed only for the Klein 9B model (non-commercial license). Select "Read access to contents of all public gated repos you can access" when creating the token.
3. **Domain and Cloudflare token** (production only) — your domain name and a Cloudflare API token with Zone DNS Edit permissions.
4. **Admin account** — email, username, and password for the first admin user.

Installation takes 10-20 minutes depending on internet speed.

## How It Works

The installer detects that Docker is available and uses it for the app stack:

- **Docker Compose** runs the backend, frontend (built into Caddy), PostgreSQL, and Redis
- **systemd** manages ComfyUI and Ollama as host services
- **Caddy** (inside Docker) handles reverse proxying and SSL via the Cloudflare DNS plugin
- Docker containers reach host GPU services via `host.docker.internal`

## Production Setup

For production mode, you need:

- A domain with DNS managed by Cloudflare
- A Cloudflare API token (My Profile > API Tokens > Create Token > Zone DNS Edit + Zone Read)
- An A record pointing your domain to your server's IP
- Cloudflare SSL/TLS mode set to **Full (strict)**

The installer handles SSL cert provisioning automatically via Caddy's ACME DNS challenge.

## Useful Commands

```bash
# App logs
cd /opt/oig && docker compose logs -f
cd /opt/oig && docker compose logs -f backend

# GPU service logs
sudo journalctl -u comfyui -f
sudo journalctl -u ollama -f

# Restart services
cd /opt/oig && docker compose up -d --build    # rebuild app
sudo systemctl restart comfyui
sudo systemctl restart ollama

# Database backup
cd /opt/oig && docker compose exec db pg_dump -U oig open_image_gen > backup.sql

# Database restore
cat backup.sql | docker compose exec -T db psql -U oig open_image_gen

# Check GPU
nvidia-smi
```

## Upgrading

```bash
bash /opt/oig/upgrade.sh
```

This backs up the database, downloads the new release, rebuilds Docker containers, and restarts services. Your `.env`, database, and S3 configuration are preserved.

## File Locations

| What | Where |
|------|-------|
| App code + Docker Compose | `/opt/oig/` |
| App config (.env) | `/opt/oig/.env` |
| ComfyUI | `/opt/ComfyUI/` |
| ComfyUI models | `/opt/ComfyUI/models/` |
| Generated images | `/opt/ComfyUI/output/` (or S3 if configured) |
| Upgrade script | `/opt/oig/upgrade.sh` |
| Backups | `/opt/oig-backups/` |

## Swap Space

The installer creates 8 GB of swap space. ComfyUI's VAE decode can spike system RAM usage significantly during high-resolution renders, and the swap prevents OOM kills on memory-constrained servers.
