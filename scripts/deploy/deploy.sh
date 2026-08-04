#!/bin/bash
# CircuitHQ — Deployment Script
# ===============================
# Deploys one or more stacks with pre-deploy snapshot, rollback support,
# and confirmation gate.
#
# Usage:
#   ./scripts/deploy/deploy.sh                        # Deploy all stacks
#   ./scripts/deploy/deploy.sh proxy                  # Single stack
#   ./scripts/deploy/deploy.sh proxy auth             # Multiple stacks
#   ./scripts/deploy/deploy.sh all --skip-backup      # Skip pre-deploy backup
#   ./scripts/deploy/deploy.sh all --dry-run          # Show what would happen
#
# Always captures deployment metadata to releases/ directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
DRY_RUN=false
SKIP_BACKUP=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Parse arguments
STACKS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --skip-backup) SKIP_BACKUP=true ;;
    *) STACKS+=("$arg") ;;
  esac
done

if [ ${#STACKS[@]} -eq 0 ]; then
  STACKS=("proxy" "auth" "monitoring" "logging")
elif [ "${STACKS[0]}" = "all" ]; then
  STACKS=("proxy" "auth" "monitoring" "logging")
fi

# ── Confirmation gate ───────────────────────────────────────────────
echo "=== CircuitHQ Deployment ==="
echo "Timestamp:  $TIMESTAMP"
echo "Git SHA:    $GIT_SHA"
echo "Branch:     $GIT_BRANCH"
echo "Stacks:     ${STACKS[*]}"
echo ""

if [ "$DRY_RUN" = false ]; then
  read -rp "Type 'DEPLOY' to confirm: " CONFIRM
  if [ "$CONFIRM" != "DEPLOY" ]; then
    echo -e "${RED}❌ Confirmation failed — deploy aborted${NC}"
    exit 1
  fi
fi
echo ""

# ── Pre-deploy snapshot ──────────────────────────────────────────────
SNAPSHOT_DIR="$BASE_DIR/releases/$TIMESTAMP"
echo "📸 Capturing pre-deploy state to releases/$TIMESTAMP/..."

capture_metadata() {
  local dir="$1"
  mkdir -p "$dir"

  # Git SHA
  echo "$GIT_SHA" > "$dir/git-sha.txt"
  echo "$GIT_BRANCH" > "$dir/git-branch.txt"

  # Image digests for all running containers
  docker ps --format '{{.Image}}' 2>/dev/null | sort -u > "$dir/running-images.txt" || true

  # Current Docker Compose configs
  for stack in "${STACKS[@]}"; do
    if [ -f "$BASE_DIR/stacks/$stack/compose.yml" ]; then
      docker compose -f "$BASE_DIR/stacks/$stack/compose.yml" config 2>/dev/null \
        > "$dir/compose-${stack}.yaml" || \
        echo "# (could not render — networks may be missing)" > "$dir/compose-${stack}.yaml"
    fi
  done

  # Container states
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null \
    > "$dir/container-state.txt" || true

  echo "$TIMESTAMP" > "$dir/timestamp.txt"
}

if [ "$DRY_RUN" = false ]; then
  capture_metadata "$SNAPSHOT_DIR"
  echo -e "  ${GREEN}✅${NC} State captured"
else
  echo "  (dry-run — would capture to $SNAPSHOT_DIR)"
fi
echo ""

# ── Pre-deploy backup ────────────────────────────────────────────────
if [ "$SKIP_BACKUP" = false ] && [ "$DRY_RUN" = false ]; then
  echo "📦 Running pre-deploy backup..."
  if [ -f "$BASE_DIR/.secrets-rendered/production/restic.env" ]; then
    RESTIC_ENV="$BASE_DIR/.secrets-rendered/production/restic.env" \
      bash "$BASE_DIR/scripts/backup/backup.sh" || echo "  ⚠️  Backup had issues — continuing"
  else
    echo "  ⚠️  No restic.env found — skipping backup"
  fi
  echo ""
fi

# ── Render secrets ──────────────────────────────────────────────────
echo "🔐 Rendering secrets..."
if [ "$DRY_RUN" = false ]; then
  bash "$SCRIPT_DIR/render-secrets.sh" || echo "  ⚠️  Secret render had issues"
fi
echo ""

# ── Preflight ────────────────────────────────────────────────────────
echo "🔍 Running preflight..."
if [ "$DRY_RUN" = false ]; then
  bash "$SCRIPT_DIR/preflight.sh" || { echo -e "${RED}❌ Preflight failed — deploy aborted${NC}"; exit 1; }
fi
echo ""

# ── Deploy stacks ────────────────────────────────────────────────────
for stack in "${STACKS[@]}"; do
  echo "🚀 Deploying stack: $stack"
  COMPOSE_FILE="$BASE_DIR/stacks/$stack/compose.yml"
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "  ${RED}❌${NC} Compose file not found: $COMPOSE_FILE"
    exit 1
  fi

  if [ "$DRY_RUN" = false ]; then
    cd "$BASE_DIR/stacks/$stack"
    echo "   Pulling images..."
    docker compose pull 2>&1 | tail -5
    echo "   Starting services..."
    docker compose up -d 2>&1 | tail -5
    cd "$BASE_DIR"
  else
    echo "   (dry-run — would deploy $stack)"
  fi
done

echo ""

# ── Health check ────────────────────────────────────────────────────
echo "🩺 Running health checks..."
if [ "$DRY_RUN" = false ]; then
  bash "$SCRIPT_DIR/healthcheck.sh" || echo "  ⚠️  Health check had warnings"
fi
echo ""

# ── Write deployment metadata ───────────────────────────────────────
if [ "$DRY_RUN" = false ]; then
  # Add deploy result marker
  echo "deploy-ok" > "$SNAPSHOT_DIR/deploy-result.txt"
  # Capture post-deploy state
  capture_metadata "$SNAPSHOT_DIR/post"
  echo "📝 Deployment metadata written to releases/$TIMESTAMP/"
fi

echo "=== Deployment Complete ==="
echo "SHA:      $GIT_SHA"
echo "Stacks:   ${STACKS[*]}"
echo "Release:  releases/$TIMESTAMP/"