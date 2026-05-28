#!/bin/bash
# ── OIG Release Script ──────────────────────────────────────────────
#
# Run this from the oig-installer repo to cut a new release.
# It tarballs the OIG app from a local checkout (or the current
# comfy-web-ui directory), uploads it as a GitHub Release asset
# on the oig-installer repo, and bumps the VERSION file.
#
# Prerequisites:
#   - GitHub CLI (gh) authenticated: https://cli.github.com/
#   - A local checkout of the OIG app source
#
# Usage:
#   ./release.sh <version> [path-to-oig-source]
#
# Examples:
#   ./release.sh 0.1.0 ../comfy-web-ui
#   ./release.sh 0.2.0                     # defaults to ../comfy-web-ui
#
set -e

VERSION="$1"
OIG_SOURCE="${2:-../comfy-web-ui}"

# ── Validate inputs ──────────────────────────────────────────────────
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version> [path-to-oig-source]"
    echo ""
    echo "Examples:"
    echo "  ./release.sh 0.1.0 ../comfy-web-ui"
    echo "  ./release.sh 0.2.0"
    exit 1
fi

if [ ! -d "$OIG_SOURCE/api" ] || [ ! -d "$OIG_SOURCE/app" ]; then
    echo "ERROR: '$OIG_SOURCE' doesn't look like the OIG app directory."
    echo "Expected to find api/ and app/ subdirectories."
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "ERROR: GitHub CLI (gh) is required."
    echo "Install: https://cli.github.com/"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "ERROR: GitHub CLI is not authenticated."
    echo "Run: gh auth login"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="oig-v${VERSION}.tar.gz"
TAG="v${VERSION}"

echo "=== Cutting OIG Release ${TAG} ==="
echo "Source: $(cd "$OIG_SOURCE" && pwd)"
echo ""

# ── Build the tarball ────────────────────────────────────────────────
echo "Building tarball..."

# Stage a clean copy via tar pipe (avoids symlink issues with cp on Windows).
# First tar from the source with excludes, then extract into a staging dir.
STAGING=$(mktemp -d)
STAGE_DIR="$STAGING/oig-v${VERSION}"
mkdir -p "$STAGE_DIR"

tar -cf - -C "$OIG_SOURCE" \
    --exclude='.git' \
    --exclude='.gitignore' \
    --exclude='.env' \
    --exclude='node_modules' \
    --exclude='dist' \
    --exclude='.vite' \
    --exclude='__pycache__' \
    --exclude='.pytest_cache' \
    --exclude='.mypy_cache' \
    --exclude='*.pyc' \
    --exclude='*.tar.gz' \
    --exclude='scripts/install' \
    --exclude='install.sh' \
    --exclude='setup-deploy-key.sh' \
    --exclude='release.sh' \
    --exclude='DEPLOY.md' \
    --exclude='Flux + Comfy Web UI' \
    --exclude='*.timestamp-*' \
    --exclude='~$*' \
    . | tar -xf - -C "$STAGE_DIR"

tar -czf "$SCRIPT_DIR/$TARBALL" -C "$STAGING" "oig-v${VERSION}"
rm -rf "$STAGING"

TARBALL_SIZE=$(du -h "$SCRIPT_DIR/$TARBALL" | cut -f1)
echo "Created $TARBALL ($TARBALL_SIZE)"

# ── Update VERSION file ─────────────────────────────────────────────
echo "$VERSION" > "$SCRIPT_DIR/VERSION"
echo "Updated VERSION to $VERSION"

# ── Create GitHub Release ────────────────────────────────────────────
echo ""
echo "Creating GitHub Release ${TAG}..."

# Commit the VERSION bump
cd "$SCRIPT_DIR"
git add VERSION
git commit -m "release: v${VERSION}" || echo "  (VERSION already committed)"
git push

# Create the release with the tarball attached
gh release create "$TAG" \
    "$SCRIPT_DIR/$TARBALL" \
    --title "OIG v${VERSION}" \
    --notes "Open Image Generator v${VERSION}

## Installation

\`\`\`bash
git clone https://github.com/maloriedelilah/oig-installer.git
cd oig-installer
bash install.sh
\`\`\`

Or one-liner:
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/maloriedelilah/oig-installer/main/install.sh -o /tmp/oig-install.sh && bash /tmp/oig-install.sh
\`\`\`"

# Clean up the local tarball
rm -f "$SCRIPT_DIR/$TARBALL"

echo ""
echo "=== Release ${TAG} published ==="
echo "https://github.com/maloriedelilah/oig-installer/releases/tag/${TAG}"
echo ""
echo "Users can now install with:"
echo "  curl -fsSL https://raw.githubusercontent.com/maloriedelilah/oig-installer/main/install.sh -o /tmp/oig-install.sh && bash /tmp/oig-install.sh"
