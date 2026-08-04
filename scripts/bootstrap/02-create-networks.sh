#!/bin/bash
# CircuitHQ — Create Docker Networks
# Creates all required external Docker networks idempotently
set -euo pipefail

# Network definitions: name, driver, internal, purpose
NETWORKS=(
  "circuithq-proxy:bridge:false:Traefik ↔ cloudflared, Traefik ↔ public services"
  "circuithq-public:bridge:false:Public apps that need Traefik routes"
  "circuithq-private:bridge:true:Private/admin-only services"
  "circuithq-management:bridge:true:Portainer/management dashboards"
  "circuithq-monitoring:bridge:true:Prometheus → exporters/Grafana"
  "circuithq-database:bridge:true:Database containers only"
  "circuithq-shared:bridge:false:Shared service-to-service comms"
  "circuithq-backup:bridge:true:Backup container → volume access"
  "circuithq-security:bridge:true:CrowdSec, fail2ban"
)

echo "=== Creating CircuitHQ Docker Networks ==="
echo ""

for entry in "${NETWORKS[@]}"; do
  IFS=":" read -r name driver internal purpose <<< "$entry"

  if docker network inspect "$name" &>/dev/null; then
    echo "✅ Network already exists: $name"
  else
    echo "Creating: $name ($purpose)"

    INTERNAL_FLAG=""
    if [ "$internal" = "true" ]; then
      INTERNAL_FLAG="--internal"
    fi

    docker network create \
      --driver "$driver" \
      $INTERNAL_FLAG \
      --label "circuithq.network=true" \
      --label "circuithq.purpose=$purpose" \
      "$name"
    echo "✅ Created: $name"
  fi
done

echo ""
echo "=== All networks created ==="
echo ""
docker network ls --filter label=circuithq.network=true