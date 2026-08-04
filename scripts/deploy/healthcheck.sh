#!/bin/bash
# CircuitHQ — Health Check
# ==========================
# Verifies all core services are running and responsive after deployment.
# Exits non-zero if any critical service fails health check.
#
# Usage: ./scripts/deploy/healthcheck.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERBOSE=false
[ "${1:-}" = "--verbose" ] && VERBOSE=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ERRORS=0

echo "=== CircuitHQ Health Check ==="
echo ""

# ─── Container status (name:description pairs) ─────────────────────
echo "📋 Container status:"
CONTAINERS=(
  "circuithq-traefik:Traefik reverse proxy"
  "circuithq-cloudflared:Cloudflare Tunnel"
  "circuithq-authelia:Authelia authentication"
  "circuithq-authelia-redis:Redis (sessions)"
  "circuithq-prometheus:Prometheus"
  "circuithq-grafana:Grafana"
  "circuithq-alertmanager:Alertmanager"
  "circuithq-loki:Loki"
  "circuithq-promtail:Promtail"
  "circuithq-node-exporter:Node Exporter"
  "circuithq-cadvisor:cAdvisor"
  "circuithq-blackbox-exporter:Blackbox Exporter"
  "circuithq-uptime-kuma:Uptime Kuma"
)

for entry in "${CONTAINERS[@]}"; do
  name="${entry%%:*}"
  desc="${entry#*:}"
  if docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null | grep -q "running"; then
    echo -e "  ${GREEN}✅${NC} $name ($desc)"
  else
    echo -e "  ${RED}❌${NC} $name ($desc) — NOT running"
    ERRORS=$((ERRORS + 1))
    if $VERBOSE; then
      docker ps -a --filter "name=$name" --format "   Status: {{.Status}}" 2>/dev/null || true
    fi
  fi
done
echo ""

# ── HTTP health endpoints (internal docker network) ─────────────────
echo "🌐 HTTP health endpoints (via circuithq-monitoring network):"
# Runs curl inside a throwaway container on the internal monitoring network,
# since these services do not publish host ports (least-privilege design).
health_url() {
  local name="$1" url="$2" service="$3"
  if docker run --rm --network circuithq-monitoring curlimages/curl \
      -sf -o /dev/null --max-time 5 "http://${service}${url}" 2>/dev/null; then
    echo -e "  ${GREEN}✅${NC} $name"
  else
    echo -e "  ${RED}❌${NC} $name — not responding at $service$url"
    ERRORS=$((ERRORS + 1))
  fi
}

health_url "Prometheus"    "/-/healthy"        "prometheus:9090"
health_url "Alertmanager"  "/-/healthy"        "alertmanager:9093"
health_url "Loki"          "/ready"            "loki:3100"
health_url "Grafana"       "/api/health"       "grafana:3000"
health_url "Blackbox"      "/health"           "blackbox-exporter:9115"
echo ""

# ── Docker socket ────────────────────────────────────────────────────
echo "🔌 Docker API:"
if docker info &>/dev/null; then
  echo -e "  ${GREEN}✅${NC} Docker API responsive"
else
  echo -e "  ${RED}❌${NC} Docker API not responding"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✅ All health checks passed${NC}"
else
  echo -e "${RED}❌ $ERRORS health check(s) failed${NC}"
  exit 1
fi