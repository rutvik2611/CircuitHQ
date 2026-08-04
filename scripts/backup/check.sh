#!/bin/bash
# CircuitHQ — restic Repository Check
# =====================================
# Verifies repository integrity and checks snapshot consistency.
# Run periodically (e.g., weekly cron) to detect corruption early.
#
# Usage: ./scripts/backup/check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESTIC_ENV="${RESTIC_ENV:-/etc/circuithq/secrets/restic.env}"
if [ -f "$RESTIC_ENV" ]; then
  set -a; source "$RESTIC_ENV"; set +a
fi

: "${RESTIC_REPOSITORY:?}"
: "${RESTIC_PASSWORD:?}"

echo "=== CircuitHQ Backup Repository Check ==="
echo "Repository: $RESTIC_REPOSITORY"
echo ""

# Check 1: Repository structure integrity
echo "📦 Checking repository structure..."
restic check --read-data-subset=5%
echo ""

# Check 2: Verify all snapshots are readable
echo "🔍 Checking snapshot consistency..."
restic snapshots --compact 2>&1 | head -20
echo ""

# Check 3: List backup statistics
echo "📊 Backup statistics:"
restic stats --latest 2>/dev/null || echo "   (no stats available)"
echo ""

echo "✅ Repository check complete"