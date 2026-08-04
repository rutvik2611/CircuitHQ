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

# ── HTTP health endpoints ────────────────────────────────────────────
echo "🌐 HTTP health endpoints:"
health_url() {
  local name="$1" url="$2"
  if curl -sf -o /dev/null --max-time 5 "$url" 2>/dev/null; then
    echo -e "  ${GREEN}✅${NC} $name"
  else
    echo -e "  ${RED}❌${NC} $name — not responding at $url"
    ERRORS=$((ERRORS + 1))
  fi
}

health_url "Prometheus"    "http://localhost:9090/-/healthy"
health_url "Alertmanager"  "http://localhost:9093/-/healthy"
health_url "Loki"          "http://localhost:3100/ready"
health_url "Grafana"       "http://localhost:3000/api/health"
health_url "Blackbox"      "http://localhost:9115/health"
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