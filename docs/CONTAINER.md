# Container / RunPod Deployment

This guide covers deploying OIG inside GPU containers like RunPod pods, where Docker-in-Docker is not available and the environment uses supervisord instead of systemd.

## Architecture

```
Internet → Cloudflare Tunnel (cloudflared) → Caddy (:80) → {
  /api/*  → FastAPI backend (port 8000)
  /*      → Static frontend (built files)
}

Backend → ComfyUI (localhost:8188)
Backend → Ollama  (localhost:11434)
Backend → PostgreSQL (localhost:5432)
Backend → Redis (localhost:6379)
```

Everything runs directly on the host — no Docker containers. All services are managed by supervisord. For production HTTPS, Cloudflare Tunnel provides an outbound connection to Cloudflare, so no inbound ports need to be exposed.

## Why No Docker?

GPU container platforms like RunPod restrict kernel capabilities (`--privileged` is not available). Docker's bridge networking requires `CAP_NET_ADMIN` for iptables, which isn't granted. The installer detects this automatically and falls back to direct installation via supervisord.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/maloriedelilah/oig-installer/main/install.sh -o /tmp/oig-install.sh && bash /tmp/oig-install.sh
```

The installer auto-detects that Docker can't run and switches to the direct-install path. It prompts for the same configuration as bare metal (mode, HF token, admin account).

## RunPod Specifics

**Persistent storage** — RunPod pods have a `/workspace` volume that persists across pod restarts. Everything else is ephemeral. The installer puts everything in `/opt` which is outside `/workspace`, so a pod reset requires a full reinstall. Consider symlinking large directories (like ComfyUI models) to `/workspace` to avoid re-downloading.

**GPU compute capability** — The installer auto-detects GPU compute capability. Blackwell GPUs (sm_120, compute capability 12.0+) get PyTorch with CUDA 12.8. Older Ampere/Ada GPUs get CUDA 12.4.

**No swap** — Container environments can't create swap files. The installer detects this and skips swap setup.

## Production Mode with Cloudflare Tunnel

RunPod doesn't expose ports directly in a way that supports custom domains. Cloudflare Tunnel solves this by creating an outbound connection from the pod to Cloudflare — no inbound ports needed.

When you choose production mode, the installer:

1. Installs `cloudflared`
2. Opens a browser for Cloudflare authentication (select the zone for your domain)
3. Creates a tunnel with a hostname-based name
4. Sets up DNS routing (`--overwrite-dns` handles existing records)
5. Configures supervisord to keep the tunnel running

The tunnel routes `https://your-domain.com` → `http://localhost:80` inside the pod, where Caddy serves the app.

**Important:** RunPod proxy URLs (`https://<pod-id>-443.proxy.runpod.net`) cannot be used as CNAME targets in Cloudflare due to cross-user restrictions. Cloudflare Tunnel is the correct solution.

## Useful Commands

```bash
# Service status
supervisorctl status

# Logs
tail -f /var/log/oig-backend.log
tail -f /var/log/caddy.log
tail -f /var/log/comfyui.log
tail -f /var/log/ollama.log
tail -f /var/log/cloudflared.log    # production only

# Restart individual services
supervisorctl restart oig-backend
supervisorctl restart caddy
supervisorctl restart comfyui
supervisorctl restart ollama
supervisorctl restart cloudflared   # production only

# Restart all
supervisorctl restart all

# Database access
sudo -u postgres psql open_image_gen

# Check GPU
nvidia-smi
```

## Upgrading

```bash
bash /opt/oig/upgrade.sh
```

This works the same as bare metal — backs up the database, downloads the new release, rebuilds the frontend, installs pip dependencies, runs migrations, and restarts services. The Cloudflare Tunnel, `.env`, and database are preserved.

## File Locations

| What | Where |
|------|-------|
| App code | `/opt/oig/` |
| App config (.env) | `/opt/oig/.env` |
| Backend venv | `/opt/oig/api/venv/` |
| Built frontend | `/opt/oig/app/dist/` |
| ComfyUI | `/opt/ComfyUI/` |
| ComfyUI models | `/opt/ComfyUI/models/` |
| Generated images | `/opt/ComfyUI/output/` (or S3 if configured) |
| Supervisor configs | `/etc/supervisor/conf.d/` |
| Caddy config | `/etc/caddy/Caddyfile` |
| Service logs | `/var/log/*.log` |
| Upgrade script | `/opt/oig/upgrade.sh` |
| Backups | `/opt/oig-backups/` |

## Troubleshooting

**cloudflared shows "No ingress rules"** — Make sure the supervisor config runs the tunnel with `--url http://localhost:80`. Check: `cat /etc/supervisor/conf.d/cloudflared.conf`.

**Cloudflare error 1033 (tunnel not resolving)** — The DNS CNAME may point to an old tunnel. Run `cloudflared tunnel route dns --overwrite-dns <tunnel-name> <domain>` to update it.

**Redis port conflict** — If Redis fails to start, a daemonized instance may be running. Kill it with `redis-cli shutdown`, then `supervisorctl restart redis`.

**Backend won't start after upgrade** — Check `tail -f /var/log/oig-backend.log`. Common cause: new pip dependencies not installed. The backend's `start.sh` runs `alembic upgrade head` on every start, but pip dependencies need to be installed manually if the venv already exists. Run: `cd /opt/oig/api && source venv/bin/activate && pip install -r requirements.txt`.
