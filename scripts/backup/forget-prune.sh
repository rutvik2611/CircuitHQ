#!/bin/bash
# CircuitHQ — restic Retention Policy (Forget + Prune)
# ======================================================
# Enforces backup retention policy to bound storage growth.
# Run automatically after successful backup.sh, or manually.
#
# Retention policy:
#   Hourly:   24 (keep last 24 hours)
#   Daily:    7  (keep last 7 days)
#   Weekly:   4  (keep last 4 weeks)
#   Monthly:  3  (keep last 3 months)
#   Yearly:   1  (keep last 1 year)
#
# Usage: ./scripts/backup/forget-prune.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN="${1:-}"

RESTIC_ENV="${RESTIC_ENV:-/etc/circuithq/secrets/restic.env}"
if [ -f "$RESTIC_ENV" ]; then
  set -a; source "$RESTIC_ENV"; set +a
fi

: "${RESTIC_REPOSITORY:?}"
: "${RESTIC_PASSWORD:?}"

echo "=== CircuitHQ Backup Retention Policy ==="
echo "Repository: $RESTIC_REPOSITORY"
echo ""

FORGET_OPTS="--keep-hourly 24 --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --keep-yearly 1"
[ "$DRY_RUN" = "--dry-run" ] && FORGET_OPTS="$FORGET_OPTS --dry-run"

# List current snapshots before pruning
echo "📋 Current snapshots:"
restic snapshots --compact 2>&1 | tail -5
echo ""

# Apply retention
echo "🗑️  Applying retention policy..."
restic forget $FORGET_OPTS
echo ""

# Prune unreferenced data (slow — runs only when forget removed data)
if [ "$DRY_RUN" != "--dry-run" ]; then
  echo "🧹 Pruning unreferenced data..."
  restic prune
fi

echo ""
echo "✅ Retention policy applied"
restic snapshots --compact 2>&1 | tail -5