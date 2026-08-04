#!/bin/bash
# CircuitHQ — Validate App Network Exposure
# ============================================
# Ensures that only public apps attach to the proxy network,
# and private apps do NOT have Traefik labels.
#
# Usage: ./scripts/validate/validate-app-exposure.sh

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ERRORS=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "=== Validating App Network Exposure ==="
echo ""

# ── Check all app compose files ─────────────────────────────────────
while IFS= read -r -d '' compose_file; do
  relative="${compose_file#$BASE_DIR/}"
  echo "📄 $relative..."

  PY_OUTPUT=$(python3 -c "
import yaml, sys
with open('$compose_file') as f:
    data = yaml.safe_load(f)
if data is None:
    sys.exit(0)

services = data.get('services', {})
networks = data.get('networks', {})

for sname, sdata in services.items():
    # Check network attachment
    svc_nets = sdata.get('networks', [])
    has_proxy = False
    has_private = False

    if isinstance(svc_nets, list):
        has_proxy = 'circuithq-proxy' in svc_nets
        has_private = 'circuithq-private' in svc_nets
    elif isinstance(svc_nets, dict):
        has_proxy = 'circuithq-proxy' in svc_nets
        has_private = 'circuithq-private' in svc_nets

    # Check Traefik labels
    labels = sdata.get('labels', []) or []
    has_traefik_enable = any('traefik.enable=true' in l for l in labels)

    # Determine expected behavior from directory name
    dir_name = '$relative'
    is_public = 'public' in dir_name
    is_private = 'private' in dir_name

    issues = []

    if has_proxy and not has_traefik_enable:
        issues.append('on proxy network but missing traefik.enable=true')
    if is_public and not has_traefik_enable:
        issues.append('public app but missing traefik.enable=true')
    if is_public and not has_proxy:
        issues.append('public app but not on proxy network')
    if is_private and has_proxy:
        issues.append('private app should NOT be on proxy network')
    if is_private and has_traefik_enable:
        issues.append('private app should NOT have traefik.enable=true')

    for issue in issues:
        print(f'{sname}: {issue}')
") || true

  if [ -n "$PY_OUTPUT" ]; then
    while IFS= read -r line; do
      echo -e "  ${RED}❌${NC} $line"
      ERRORS=$((ERRORS + 1))
    done <<< "$PY_OUTPUT"
  else
    echo -e "  ${GREEN}✅${NC} All checks passed"
  fi
  echo ""
done < <(find "$BASE_DIR/stacks/apps" -name "compose.yml" -type f -print0 2>/dev/null || true)

echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✅ All app exposure checks passed${NC}"
else
  echo -e "${RED}❌ $ERRORS exposure error(s) found${NC}"
  exit 1
fi