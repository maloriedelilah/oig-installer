#!/bin/bash
# ── Ollama Installation ──────────────────────────────────────────────
# Expects HAS_SYSTEMD to be set by the parent install.sh.
set -e

HAS_SYSTEMD="${HAS_SYSTEMD:-0}"

echo "=== Installing Ollama ==="

if command -v ollama &>/dev/null; then
    echo "Ollama is already installed."
else
    echo "Downloading and installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# ── Helper: wait for Ollama API ──────────────────────────────────────
wait_for_ollama() {
    for _ in {1..30}; do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# ── Start & configure Ollama ─────────────────────────────────────────
if [ "$HAS_SYSTEMD" = "1" ]; then
    # ── systemd path (normal Linux servers) ──────────────────────────
    sudo systemctl start ollama 2>/dev/null || true

    echo "Waiting for Ollama to start..."
    if ! wait_for_ollama; then
        echo "ERROR: Ollama didn't start within 30 seconds."
        echo "Try: sudo systemctl start ollama"
        exit 1
    fi

    echo "Configuring Ollama to listen on 0.0.0.0 (for Docker access)..."
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    cat <<'EOF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart ollama

    echo "Waiting for Ollama to restart..."
    if ! wait_for_ollama; then
        echo "WARNING: Ollama didn't come back after config change. Continuing..."
    fi
else
    # ── supervisord path (RunPod, containers) ────────────────────────
    # Install supervisor if not present
    if ! command -v supervisord &>/dev/null; then
        echo "Installing supervisord (process manager)..."
        apt-get update -qq
        apt-get install -y -qq supervisor
    fi

    # Ensure supervisor is running
    if ! pgrep -x supervisord &>/dev/null; then
        supervisord -c /etc/supervisor/supervisord.conf 2>/dev/null || true
    fi

    echo "Creating Ollama supervisor config..."
    mkdir -p /etc/supervisor/conf.d
    cat > /etc/supervisor/conf.d/ollama.conf <<'EOF'
[program:ollama]
command=/usr/local/bin/ollama serve
environment=OLLAMA_HOST="0.0.0.0"
autostart=true
autorestart=true
startsecs=5
startretries=3
stdout_logfile=/var/log/ollama.log
stderr_logfile=/var/log/ollama.log
EOF

    supervisorctl reread 2>/dev/null || true
    supervisorctl update 2>/dev/null || true
    supervisorctl start ollama 2>/dev/null || true

    echo "Waiting for Ollama to start..."
    if ! wait_for_ollama; then
        echo "ERROR: Ollama didn't start within 30 seconds."
        echo "Check: tail -f /var/log/ollama.log"
        exit 1
    fi
fi

echo "Ollama is running."

# ── Pull the base model ──────────────────────────────────────────────
echo "Pulling qwen3:8b model (this may take a few minutes)..."
ollama pull qwen3:8b

# Create a nothink variant — bakes /no_think into the chat template so the
# model never wastes tokens on chain-of-thought reasoning for prompt rewrites.
echo "Creating qwen3:8b-nothink model..."
cat << 'MODELFILE' > /tmp/Modelfile
FROM qwen3:8b
PARAMETER num_ctx 4096
TEMPLATE """{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{- range .Messages }}{{- if eq .Role "user" }}<|im_start|>user
{{ .Content }} /no_think<|im_end|>
{{ else if eq .Role "assistant" }}<|im_start|>assistant
{{ .Content }}<|im_end|>
{{ end }}{{- end }}<|im_start|>assistant
"""
MODELFILE
ollama create qwen3:8b-nothink -f /tmp/Modelfile
rm -f /tmp/Modelfile

# Pull a vision model for image safety screening (img2img uploads)
echo ""
echo "Pulling llava:7b vision model for image safety screening..."
ollama pull llava:7b

echo "Ollama is ready."
echo ""
