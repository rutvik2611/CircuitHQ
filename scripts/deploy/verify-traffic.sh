#!/bin/bash
# CircuitHQ — Verify Traffic
# ============================
# Sends synthetic traffic through ingress to verify end-to-end connectivity.
# Checks: public ingress (via Traefik), Authelia forward-auth, internal services.
#
# Usage: ./scripts/deploy/verify-traffic.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERBOSE=false
[ "${1:-}" = "--verbose" ] && VERBOSE=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ERRORS=0

echo "=== CircuitHQ Traffic Verification ==="
echo ""

# ── Traefik ping (internal docker network) ─────────────────────────
echo "🔄 Traefik ping:"
if docker run --rm --network circuithq-monitoring curlimages/curl \
    -sf --max-time 5 "http://traefik:8080/ping" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✅${NC} Traefik ping OK"
else
  echo -e "  ${RED}❌${NC} Traefik ping failed"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── Traefik metrics (prometheus format) ──────────────────────────────
echo "📊 Traefik metrics endpoint:"
if docker run --rm --network circuithq-monitoring curlimages/curl \
    -sf --max-time 5 "http://traefik:8080/metrics" 2>/dev/null | grep -q "traefik_"; then
  echo -e "  ${GREEN}✅${NC} Traefik metrics contain traefik_ prefix"
else
  echo -e "  ${YELLOW}⚠️${NC} Traefik metrics not available or empty"
fi
echo ""

# ── Prometheus targets ──────────────────────────────────────────────
echo "🎯 Prometheus targets (up count):"
UP_COUNT=$(docker run --rm --network circuithq-monitoring curlimages/curl \
  -sf --max-time 5 "http://prometheus:9090/api/v1/targets" 2>/dev/null \
  | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    targets = data['data']['activeTargets']
    up = sum(1 for t in targets if t['health'] == 'up')
    total = len(targets)
    print(f'{up}/{total}')
except: print('N/A')
" 2>/dev/null || echo "N/A")
echo "   $UP_COUNT targets up"
echo ""

# ── Grafana health ───────────────────────────────────────────────────
echo "📈 Grafana API:"
GRAFANA_OK=$(docker run --rm --network circuithq-monitoring curlimages/curl \
  -sf --max-time 5 "http://grafana:3000/api/health" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('database','N/A'))" 2>/dev/null || echo "N/A")
if [ "$GRAFANA_OK" = "ok" ]; then
  echo -e "  ${GREEN}✅${NC} Grafana healthy (DB: $GRAFANA_OK)"
else
  echo -e "  ${RED}❌${NC} Grafana health check failed"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── Authelia health (forward-auth simulation) ───────────────────────
echo "🔐 Authelia forward-auth (expect 401 without cookie):"
HTTP_CODE=$(docker run --rm --network circuithq-proxy curlimages/curl \
  -sf -o /dev/null -w "%{http_code}" --max-time 5 \
  "http://authelia:9091/api/authz/forward-auth" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "400" ]; then
  echo -e "  ${GREEN}✅${NC} Authelia returns $HTTP_CODE (expected for unauthenticated)"
elif [ "$HTTP_CODE" = "000" ]; then
  echo -e "  ${RED}❌${NC} Authelia not reachable"
  ERRORS=$((ERRORS + 1))
else
  echo -e "  ${YELLOW}⚠️${NC} Authelia returned HTTP $HTTP_CODE (unexpected)"
fi
echo ""

# ── Alertmanager health ──────────────────────────────────────────────
echo "🔔 Alertmanager health:"
AM_CODE=$(docker run --rm --network circuithq-monitoring curlimages/curl \
  -sf -o /dev/null -w "%{http_code}" --max-time 5 \
  "http://alertmanager:9093/-/healthy" 2>/dev/null || echo "000")
if [ "$AM_CODE" = "200" ]; then
  echo -e "  ${GREEN}✅${NC} Alertmanager healthy"
else
  echo -e "  ${RED}❌${NC} Alertmanager health failed (HTTP $AM_CODE)"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── Loki readiness ───────────────────────────────────────────────────
echo "📝 Loki readiness:"
if docker run --rm --network circuithq-monitoring curlimages/curl \
    -sf --max-time 5 "http://loki:3100/ready" > /dev/null 2>&1; then
  echo -e "  ${GREEN}✅${NC} Loki ready"
else
  echo -e "  ${RED}❌${NC} Loki not ready"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✅ All traffic checks passed${NC}"
else
  echo -e "${RED}❌ $ERRORS traffic check(s) failed${NC}"
  exit 1
fi