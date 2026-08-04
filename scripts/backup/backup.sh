#!/bin/bash
# CircuitHQ — restic Backup Script
# ==================================
# Encrypted backup of repo, configs, volumes, certs, and logs to remote restic repository.
#
# Usage:
#   ./scripts/backup/backup.sh                    # Run full backup
#   ./scripts/backup/backup.sh --dry-run          # Show what would be backed up
#   ./scripts/backup/backup.sh --verbose          # Detailed output
#
# Configuration via environment (SOPS-decrypted at runtime):
#   RESTIC_REPOSITORY  — restic repo URL (s3:s3.amazonaws.com/bucket, rclone:remote:path, /local/path)
#   RESTIC_PASSWORD    — repository encryption password
#   AWS_ACCESS_KEY_ID  — for S3 repos
#   AWS_SECRET_ACCESS_KEY — for S3 repos
#   RESTIC_CACHE_DIR   — cache directory (default: ~/.cache/restic)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="/var/log/circuithq/backup-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Prerequisites ──────────────────────────────────────────────────
command -v restic &>/dev/null || { err "restic not found. Install: brew install restic"; exit 1; }
command -v docker &>/dev/null || { err "docker not found."; exit 1; }

# Load SOPS-decrypted restic env (if available)
RESTIC_ENV="${RESTIC_ENV:-/etc/circuithq/secrets/restic.env}"
if [ -f "$RESTIC_ENV" ]; then
  set -a; source "$RESTIC_ENV"; set +a
fi

# Validate required vars
: "${RESTIC_REPOSITORY:?Must set RESTIC_REPOSITORY}"
: "${RESTIC_PASSWORD:?Must set RESTIC_PASSWORD}"

export RESTIC_REPOSITORY RESTIC_PASSWORD
RESTIC_OPTS=""
[ "$DRY_RUN" = "true" ] && RESTIC_OPTS="$RESTIC_OPTS --dry-run"
[ "$VERBOSE" = "true" ] && RESTIC_OPTS="$RESTIC_OPTS --verbose"

# ── Backup Sources ─────────────────────────────────────────────────

log "Starting CircuitHQ backup → ${RESTIC_REPOSITORY}"
log ""

# 1. Repo root (git-tracked configs, compose files, scripts)
log "📁 Backing up repository config..."
restic backup $RESTIC_OPTS \
  --tag "circuithq" \
  --tag "repo" \
  --tag "$TIMESTAMP" \
  --exclude=".git" \
  --exclude="backups/" \
  --exclude="*.tar.gz" \
  --exclude="secrets/**/credentials.json" \
  "$BASE_DIR"

# 2. Docker volumes (via temporary containers)
log "📦 Backing up Docker volumes..."
VOLUMES=(
  "circuithq-prometheus-data"
  "circuithq-grafana-data"
  "circuithq-loki-data"
  "circuithq-traefik-acme"
  "circuithq-redis-data"
  "circuithq-uptime-kuma-data"
  "circuithq-authelia-config"
)

for vol in "${VOLUMES[@]}"; do
  if docker volume inspect "$vol" &>/dev/null; then
    log "   Volume: $vol"
    if [ "$DRY_RUN" != "true" ]; then
      restic backup $RESTIC_OPTS \
        --tag "circuithq" \
        --tag "volume" \
        --tag "$vol" \
        --tag "$TIMESTAMP" \
        --stdin \
        --stdin-filename "volumes/${vol}.tar" \
        < <(docker run --rm -v "${vol}:/source:ro" alpine tar czf - -C /source .)
    fi
  else
    warn "   Volume $vol not found — skipping"
  fi
done

# 3. Database dumps (if containers running)
log "🗄️  Backing up database dumps..."
if docker ps --format '{{.Names}}' | grep -q postgres; then
  if [ "$DRY_RUN" != "true" ]; then
    docker exec circuithq-postgres pg_dumpall -U postgres \
      | restic backup $RESTIC_OPTS \
        --tag "circuithq" \
        --tag "database" \
        --tag "postgres" \
        --tag "$TIMESTAMP" \
        --stdin \
        --stdin-filename "database/postgres.sql"
  fi
else
  warn "   No database container running — skipping database dump"
fi

# 4. ACME certs (direct file path if accessible)
log "🔐 Backing up ACME certificates..."
ACME_SRC="${ACME_SRC:-/var/lib/docker/volumes/circuithq-traefik-acme/_data}"
if [ -f "$ACME_SRC/acme.json" ]; then
  if [ "$DRY_RUN" != "true" ]; then
    restic backup $RESTIC_OPTS \
      --tag "circuithq" \
      --tag "acme" \
      --tag "$TIMESTAMP" \
      "$ACME_SRC"
  fi
else
  warn "   ACME data not found at $ACME_SRC — skipping"
fi

# 5. System logs (last 24h)
log "📋 Backing up recent system logs..."
if [ "$DRY_RUN" != "true" ]; then
  journalctl --since "24 hours ago" --output=short-iso 2>/dev/null \
    | restic backup $RESTIC_OPTS \
      --tag "circuithq" \
      --tag "logs" \
      --tag "$TIMESTAMP" \
      --stdin \
      --stdin-filename "logs/systemd-${TIMESTAMP}.log" \
    || warn "   journalctl failed — skipping system logs"
fi

# ── Backup Complete ────────────────────────────────────────────────
log ""
log "✅ Backup complete"
log "   Repository: ${RESTIC_REPOSITORY}"

# Send push notification to Uptime Kuma (if configured)
PUSH_URL="${UPTIME_KUMA_PUSH_URL:-}"
if [ -n "$PUSH_URL" ] && [ "$DRY_RUN" != "true" ]; then
  curl -s -o /dev/null "$PUSH_URL" && log "   Uptime Kuma notified" || warn "   Uptime Kuma push failed"
fi

# Run forget/prune after successful backup
if [ "$DRY_RUN" != "true" ]; then
  log "   Running retention policy..."
  bash "$SCRIPT_DIR/backup/forget-prune.sh" 2>>"$LOG_FILE" || warn "   Retention policy had warnings"
fi