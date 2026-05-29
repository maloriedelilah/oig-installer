#!/bin/bash
# ── Open Image Generator — Upgrade Script ─────────────────────────────
#
# Usage:
#   bash upgrade.sh
#   — or remotely —
#   curl -fsSL https://raw.githubusercontent.com/maloriedelilah/oig-installer/main/upgrade.sh -o /tmp/oig-upgrade.sh && bash /tmp/oig-upgrade.sh
#
# Features:
#   • Checks if an upgrade is available before doing anything
#   • Backs up the database before upgrading
#   • Keeps the previous release tarball for rollback
#   • Re-runs the installer (idempotent — skips already-installed deps)
#
set -e

# ── Colours ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALLER_REPO="maloriedelilah/oig-installer"
INSTALLER_BRANCH="main"
APP_DIR="/opt/oig"
BACKUP_DIR="/opt/oig-backups"

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║           Open Image Generator — Upgrade                 ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Check current version ────────────────────────────────────────────
if [ -f "$APP_DIR/.oig-version" ]; then
    CURRENT_VERSION=$(cat "$APP_DIR/.oig-version" | tr -d '[:space:]')
    echo -e "Installed version: ${BOLD}v${CURRENT_VERSION}${NC}"
else
    echo -e "${YELLOW}No existing installation found. Running full installer.${NC}"
    echo ""
    curl -fsSL "https://raw.githubusercontent.com/$INSTALLER_REPO/$INSTALLER_BRANCH/install.sh" -o /tmp/oig-install.sh && bash /tmp/oig-install.sh
    exit $?
fi

# ── Check latest version ────────────────────────────────────────────
echo "Checking for updates..."
LATEST_VERSION=$(curl -fsSL "https://raw.githubusercontent.com/$INSTALLER_REPO/$INSTALLER_BRANCH/VERSION" | tr -d '[:space:]')

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${RED}Could not fetch latest version. Check your internet connection.${NC}"
    exit 1
fi

echo -e "Latest version:    ${BOLD}v${LATEST_VERSION}${NC}"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo ""
    echo -e "${GREEN}Already up to date!${NC} No upgrade needed."
    echo ""
    exit 0
fi

echo ""
echo -e "${GREEN}Upgrade available:${NC} v${CURRENT_VERSION} → v${LATEST_VERSION}"
echo ""

# ── Pre-upgrade database backup ──────────────────────────────────────
echo "Backing up database..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/oig-db-v${CURRENT_VERSION}-$(date +%Y%m%d-%H%M%S).sql.gz"

# Load database credentials from .env
if [ -f "$APP_DIR/.env" ]; then
    POSTGRES_USER=$(grep "^POSTGRES_USER=" "$APP_DIR/.env" | cut -d= -f2)
    POSTGRES_DB=$(grep "^POSTGRES_DB=" "$APP_DIR/.env" | cut -d= -f2)
    POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$APP_DIR/.env" | cut -d= -f2)
fi

POSTGRES_USER="${POSTGRES_USER:-oig}"
POSTGRES_DB="${POSTGRES_DB:-open_image_gen}"

if command -v pg_dump &>/dev/null; then
    if sudo -u postgres pg_dump "$POSTGRES_DB" 2>/dev/null | gzip > "$BACKUP_FILE"; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo -e "  ${GREEN}Database backed up:${NC} $BACKUP_FILE ($BACKUP_SIZE)"
    else
        # Try with password auth (Docker setup)
        if PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -h localhost "$POSTGRES_DB" 2>/dev/null | gzip > "$BACKUP_FILE"; then
            BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            echo -e "  ${GREEN}Database backed up:${NC} $BACKUP_FILE ($BACKUP_SIZE)"
        else
            echo -e "  ${YELLOW}Database backup failed (non-fatal). Continuing with upgrade.${NC}"
            rm -f "$BACKUP_FILE"
        fi
    fi
else
    echo -e "  ${YELLOW}pg_dump not found — skipping database backup.${NC}"
fi

# ── Save previous release for rollback ───────────────────────────────
echo "Saving current release for rollback..."
ROLLBACK_DIR="$BACKUP_DIR/rollback-v${CURRENT_VERSION}"
if [ -d "$APP_DIR/api" ] && [ -d "$APP_DIR/app" ]; then
    rm -rf "$ROLLBACK_DIR"
    mkdir -p "$ROLLBACK_DIR"
    cp -a "$APP_DIR/api" "$ROLLBACK_DIR/api"
    cp -a "$APP_DIR/app" "$ROLLBACK_DIR/app"
    [ -f "$APP_DIR/.oig-version" ] && cp "$APP_DIR/.oig-version" "$ROLLBACK_DIR/.oig-version"
    echo -e "  ${GREEN}Saved to:${NC} $ROLLBACK_DIR"
else
    echo -e "  ${YELLOW}Could not find app files to save.${NC}"
fi

# ── Clean up old backups (keep last 3) ───────────────────────────────
echo "Cleaning up old backups..."
# DB backups — keep newest 3
ls -t "$BACKUP_DIR"/oig-db-*.sql.gz 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true
# Rollback dirs — keep newest 3
ls -dt "$BACKUP_DIR"/rollback-v* 2>/dev/null | tail -n +4 | xargs rm -rf 2>/dev/null || true

# ── Run the installer (handles the actual upgrade) ───────────────────
echo ""
echo -e "${BOLD}Running installer...${NC}"
echo ""
curl -fsSL "https://raw.githubusercontent.com/$INSTALLER_REPO/$INSTALLER_BRANCH/install.sh" -o /tmp/oig-install.sh && bash /tmp/oig-install.sh

# ── Post-upgrade summary ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}Upgrade complete!${NC}"
echo ""
echo "  To rollback if needed:"
echo "    1. Stop services"
echo "    2. Restore files:  cp -a $ROLLBACK_DIR/* $APP_DIR/"
echo "    3. Restore DB:     gunzip -c $BACKUP_FILE | sudo -u postgres psql $POSTGRES_DB"
echo "    4. Restart services"
echo ""
