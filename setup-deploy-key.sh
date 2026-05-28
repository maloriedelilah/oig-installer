#!/bin/bash
# Generate a deploy key and print the public key for adding to your Git host
set -e

KEY_FILE="$HOME/.ssh/deploy_key"

if [ -f "$KEY_FILE" ]; then
  echo "Deploy key already exists at $KEY_FILE"
else
  ssh-keygen -t ed25519 -C "deploy@$(hostname)" -f "$KEY_FILE" -N ""
  echo ""
fi

# Configure SSH to use this key for GitHub/GitLab
if ! grep -q "deploy_key" ~/.ssh/config 2>/dev/null; then
  cat >> ~/.ssh/config <<EOF

Host github.com
  IdentityFile $KEY_FILE
  IdentitiesOnly yes
EOF
  chmod 600 ~/.ssh/config
  echo "Added SSH config entry for github.com"
fi

echo ""
echo "=== Add this public key to your repo's deploy keys ==="
echo ""
cat "${KEY_FILE}.pub"
echo ""
echo "GitHub: Settings → Deploy keys → Add deploy key"
echo "GitLab: Settings → Repository → Deploy keys"
