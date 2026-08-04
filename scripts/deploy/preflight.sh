#!/bin/bash
# CircuitHQ — Preflight Checks
# ==============================
# Runs before deployment to verify host readiness.
# Exits non-zero if any critical check fails.
#
# Usage: ./scripts/deploy/preflight.sh [--strict]
#   --strict  Fail on warnings too (for CI use)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRICT=false
[ "${1:-}" = "--strict" ] && STRICT=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ERRORS=0
WARNINGS=0

echo "=== CircuitHQ Preflight Checks ==="
echo ""

# ── Git state ────────────────────────────────────────────────────────
echo "📦 Git state:"
cd "$BASE_DIR"
echo "   Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')"
echo "   SHA:    $(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
echo "   Dirty:  $(git status --porcelain | wc -l | tr -d ' ') changed files"
if [ "$(git status --porcelain | wc -l)" -gt 0 ]; then
  echo -e "  ${YELLOW}⚠️${NC} Repo has uncommitted changes — deploy will use current working tree"
  WARNINGS=$((WARNINGS + 1))
fi
echo ""

# ── Docker ───────────────────────────────────────────────────────────
echo "🐳 Docker:"
if docker info &>/dev/null; then
  echo -e "  ${GREEN}✅${NC} Docker daemon running"
else
  echo -e "  ${RED}❌${NC} Docker daemon NOT running"
  ERRORS=$((ERRORS + 1))
fi

DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'N/A')
echo "   Version: $DOCKER_VERSION"

if docker compose version &>/dev/null; then
  echo -e "  ${GREEN}✅${NC} Docker Compose available"
else
  echo -e "  ${RED}❌${NC} Docker Compose NOT available"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── Required networks ────────────────────────────────────────────────
echo "🌐 Required Docker networks:"
for net in circuithq-proxy circuithq-monitoring circuithq-security circuithq-public; do
  if docker network inspect "$net" &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} $net"
  else
    echo -e "  ${YELLOW}⚠️${NC} $net missing — will be created"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# ── Required volumes ─────────────────────────────────────────────────
echo "💾 Required Docker volumes:"
for vol in circuithq-traefik-acme circuithq-redis-data circuithq-prometheus-data \
           circuithq-grafana-data circuithq-loki-data circuithq-uptime-kuma-data; do
  if docker volume inspect "$vol" &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} $vol"
  else
    echo -e "  ${YELLOW}⚠️${NC} $vol missing — will be created"
    WARNINGS=$((WARNINGS + 1))
  fi
done
echo ""

# ── SOPS / age key ───────────────────────────────────────────────────
echo "🔐 Secret management:"
AGE_KEY="$HOME/.config/sops/age/keys.txt"
if [ -f "$AGE_KEY" ]; then
  PERMS=$(stat -f "%Lp" "$AGE_KEY" 2>/dev/null || stat -c "%a" "$AGE_KEY" 2>/dev/null)
  echo -e "  ${GREEN}✅${NC} age key present ($PERMS)"
else
  echo -e "  ${RED}❌${NC} age key NOT found at $AGE_KEY"
  ERRORS=$((ERRORS + 1))
fi

if command -v sops &>/dev/null; then
  echo -e "  ${GREEN}✅${NC} sops installed"
else
  echo -e "  ${RED}❌${NC} sops NOT installed"
  ERRORS=$((ERRORS + 1))
fi

if [ -f "$BASE_DIR/.secrets-rendered/production/restic.env" ]; then
  echo -e "  ${GREEN}✅${NC} Rendered secrets exist"
else
  echo -e "  ${YELLOW}⚠️${NC} No rendered secrets found — run render-secrets.sh"
  WARNINGS=$((WARNINGS + 1))
fi
echo ""

# ── Disk space ───────────────────────────────────────────────────────
echo "💿 Disk space:"
AVAIL=$(df -h / | awk 'NR==2 {print $4}')
USED=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
echo "   Available: $AVAIL  (${USED}% used)"
if [ "$USED" -gt 85 ]; then
  echo -e "  ${RED}❌${NC} Disk usage >85% — deploy may fail"
  ERRORS=$((ERRORS + 1))
elif [ "$USED" -gt 75 ]; then
  echo -e "  ${YELLOW}⚠️${NC} Disk usage >75% — monitor closely"
  WARNINGS=$((WARNINGS + 1))
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────
echo "=== Summary ==="
echo -e "  Errors:   ${RED}$ERRORS${NC}"
echo -e "  Warnings: ${YELLOW}$WARNINGS${NC}"

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}❌ Preflight FAILED — fix errors before deploying${NC}"
  exit 1
fi
if [ "$STRICT" = true ] && [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Strict mode: warnings treated as errors${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Preflight passed${NC}"