#!/bin/bash
# ── Ollama Installation ──────────────────────────────────────────────
set -e

echo "=== Installing Ollama ==="

if command -v ollama &>/dev/null; then
    echo "Ollama is already installed."
else
    echo "Downloading and installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
for _ in {1..30}; do
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        break
    fi
    sleep 1
done

if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo "ERROR: Ollama didn't start within 30 seconds."
    echo "Try: sudo systemctl start ollama"
    exit 1
fi

# Configure Ollama to listen on all interfaces (for Docker containers)
echo "Configuring Ollama to listen on 0.0.0.0 (for Docker access)..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat <<'EOF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama

# Wait for restart
echo "Waiting for Ollama to restart..."
for _ in {1..30}; do
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        break
    fi
    sleep 1
done

# Pull the LLM model
echo "Pulling qwen3:8b model (this may take a few minutes)..."
ollama pull qwen3:8b

echo "Ollama is ready."
echo ""
