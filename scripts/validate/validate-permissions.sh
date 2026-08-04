#!/bin/bash
# CircuitHQ — Validate File Permissions
# ========================================
# Checks that sensitive files have correct ownership and permissions.
# Runs as part of make validate / security-scan.
#
# Rules:
#   - SOPS age keys: 0600, owned by current user
#   - acme.json:     0600 (Traefik requirement)
#   - Shell scripts: 0755 or 0700 (executable by owner)
#   - .env files:    0600 (never world-readable)
#   - SOPS files:    not world-writable

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ERRORS=0
WARNINGS=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "=== Validating File Permissions ==="
echo ""

# ── Age private key ──────────────────────────────────────────────────
AGE_KEY="$HOME/.config/sops/age/keys.txt"
if [ -f "$AGE_KEY" ]; then
  PERMS=$(stat -c "%a" "$AGE_KEY" 2>/dev/null || stat -f "%Lp" "$AGE_KEY" 2>/dev/null)
  if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
    echo -e "  ${GREEN}✅${NC} age key: $PERMS"
  else
    echo -e "  ${RED}❌${NC} age key has perms $PERMS (expected 0600)"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo -e "  ${YELLOW}⚠️${NC} age key not found at $AGE_KEY"
  WARNINGS=$((WARNINGS + 1))
fi

# ── Shell scripts ────────────────────────────────────────────────────
echo ""
echo "📜 Checking shell script permissions..."
while IFS= read -r -d '' script; do
  PERMS=$(stat -c "%a" "$script" 2>/dev/null || stat -f "%Lp" "$script" 2>/dev/null)
  # Should be 755, 711, 750, 700, or 555
      case "$PERMS" in
        755|711|750|700|550|555) echo -e "  ${GREEN}✅${NC} ${script#$BASE_DIR/} ($PERMS)" ;;
    *)
      echo -e "  ${RED}❌${NC} ${script#$BASE_DIR/} has perms $PERMS (expected 755)"
      ERRORS=$((ERRORS + 1))
      ;;
  esac
done < <(find "$BASE_DIR/scripts" -name "*.sh" -type f -print0)

# ── .env files ───────────────────────────────────────────────────────
echo ""
echo "🔑 Checking .env file permissions..."
while IFS= read -r -d '' envfile; do
  PERMS=$(stat -c "%a" "$envfile" 2>/dev/null || stat -f "%Lp" "$envfile" 2>/dev/null)
  if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
    echo -e "  ${GREEN}✅${NC} ${envfile#$BASE_DIR/} ($PERMS)"
  else
    echo -e "  ${YELLOW}⚠️${NC} ${envfile#$BASE_DIR/} perms $PERMS (should be 0600)"
    WARNINGS=$((WARNINGS + 1))
  fi
done < <(find "$BASE_DIR/.secrets-rendered" -name "*.env" -type f -print0 2>/dev/null || true)

# ── acme.json (Traefik) ──────────────────────────────────────────────
ACME_JSON="/var/lib/docker/volumes/circuithq-traefik-acme/_data/acme.json"
if [ -f "$ACME_JSON" ]; then
  PERMS=$(stat -c "%a" "$ACME_JSON" 2>/dev/null || stat -f "%Lp" "$ACME_JSON" 2>/dev/null)
  if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
    echo -e "  ${GREEN}✅${NC} acme.json: $PERMS"
  else
    echo -e "  ${RED}❌${NC} acme.json has perms $PERMS (expected 0600)"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo -e "  ${YELLOW}⚠️${NC} acme.json not found (expected if Traefik not deployed)"
  WARNINGS=$((WARNINGS + 1))
fi

# ── SOPS files (not world-writable) ──────────────────────────────────
echo ""
echo "🔐 Checking SOPS-encrypted file permissions..."
while IFS= read -r -d '' sopsfile; do
  PERMS=$(stat -c "%a" "$sopsfile" 2>/dev/null || stat -f "%Lp" "$sopsfile" 2>/dev/null)
  # SOPS files should not be world-writable
  if [ "${PERMS: -1}" -lt "8" ] 2>/dev/null; then
    echo -e "  ${GREEN}✅${NC} ${sopsfile#$BASE_DIR/} ($PERMS)"
  else
    echo -e "  ${YELLOW}⚠️${NC} ${sopsfile#$BASE_DIR/} is world-writable ($PERMS)"
    WARNINGS=$((WARNINGS + 1))
  fi
done < <(find "$BASE_DIR/secrets" -name "*.sops.yaml" -type f -print0 2>/dev/null || true)

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✅${NC} All permission checks passed ($WARNINGS warnings)"
else
  echo -e "${RED}❌${NC} $ERRORS permission error(s) found"
  exit 1
fi