#!/bin/bash
# CircuitHQ — Validate Docker Networks Exist
# Checks that all required Docker networks are present on the host
set -euo pipefail

MISSING=0
REQUIRED_NETWORKS=(
  "circuithq-proxy"
  "circuithq-public"
  "circuithq-private"
  "circuithq-management"
  "circuithq-monitoring"
  "circuithq-database"
  "circuithq-shared"
  "circuithq-backup"
  "circuithq-security"
)

echo "=== Validating Docker Networks ==="
echo ""

for net in "${REQUIRED_NETWORKS[@]}"; do
  if docker network inspect "$net" &>/dev/null; then
    echo "✅ $net"
  else
    echo "❌ MISSING: $net"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
if [ "$MISSING" -eq 0 ]; then
  echo "✅ All $(( ${#REQUIRED_NETWORKS[@]} )) required networks present"
else
  echo "❌ $MISSING network(s) missing — run scripts/bootstrap/02-create-networks.sh"
  exit 1
fi