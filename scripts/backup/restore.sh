#!/bin/bash
# CircuitHQ — restic Restore Script
# ===================================
# Restore backups from restic repository.
#
# Usage:
#   ./scripts/backup/restore.sh latest                          # Restore latest snapshot
#   ./scripts/backup/restore.sh <snapshot-id>                   # Restore specific snapshot
#   ./scripts/backup/restore.sh latest --target /tmp/restore    # Restore to custom path
#   ./scripts/backup/restore.sh latest --repo                   # Restore only repo files
#   ./scripts/backup/restore.sh latest --volumes                # Restore only Docker volumes
#   ./scripts/backup/restore.sh list                            # List available snapshots

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESTORE_TARGET="${RESTORE_TARGET:-$BASE_DIR/restore-test}"
FILTER="${2:-all}"  # all, repo, volumes, logs, database, acme
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Load SOPS-decrypted restic env
RESTIC_ENV="${RESTIC_ENV:-/etc/circuithq/secrets/restic.env}"
if [ -f "$RESTIC_ENV" ]; then
  set -a; source "$RESTIC_ENV"; set +a
fi

: "${RESTIC_REPOSITORY:?Must set RESTIC_REPOSITORY}"
: "${RESTIC_PASSWORD:?Must set RESTIC_PASSWORD}"

SNAPSHOT="${1:-latest}"

# List snapshots
if [ "$SNAPSHOT" = "list" ]; then
  restic snapshots
  exit 0
fi

# Resolve "latest" to actual snapshot ID
if [ "$SNAPSHOT" = "latest" ]; then
  SNAPSHOT=$(restic snapshots --json 2>/dev/null | python3 -c "
import json,sys
snaps = json.load(sys.stdin)
if not snaps:
    sys.exit(1)
snaps.sort(key=lambda x: x['time'], reverse=True)
print(snaps[0]['short_id'])
" 2>/dev/null || echo "latest")
fi

log "Restoring snapshot: $SNAPSHOT"
log ""

# Determine which paths/tags to restore
case "$FILTER" in
  all)
    RESTORE_PATHS=("/")
    TAGS=("--tag" "circuithq")
    ;;
  repo)
    RESTORE_PATHS=("/")
    TAGS=("--tag" "repo" "--tag" "circuithq")
    ;;
  volumes)
    RESTORE_PATHS=("/volumes")
    TAGS=("--tag" "volume" "--tag" "circuithq")
    ;;
  logs)
    RESTORE_PATHS=("/logs")
    TAGS=("--tag" "logs" "--tag" "circuithq")
    ;;
  database)
    RESTORE_PATHS=("/database")
    TAGS=("--tag" "database" "--tag" "circuithq")
    ;;
  acme)
    RESTORE_PATHS=("/*")
    TAGS=("--tag" "acme" "--tag" "circuithq")
    ;;
  *)
    err "Unknown filter: $FILTER. Use: all, repo, volumes, logs, database, acme"
    exit 1
    ;;
esac

# Perform restore
mkdir -p "$RESTORE_TARGET"
restic restore "$SNAPSHOT" \
  --target "$RESTORE_TARGET" \
  "${TAGS[@]}" \
  --include "${RESTORE_PATHS[@]}" \
  --verbose

log ""
log "✅ Restored snapshot $SNAPSHOT to $RESTORE_TARGET"
log "   Verify with: ls -la $RESTORE_TARGET"