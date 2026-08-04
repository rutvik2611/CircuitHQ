# Monitoring Stack Runbook

## Prerequisites

- Docker and Docker Compose installed
- Networks exist: `circuithq-monitoring`, `circuithq-proxy`, `circuithq-public`
- Volumes exist: `circuithq-prometheus-data`, `circuithq-grafana-data`, `circuithq-uptime-kuma-data`
- Traefik stack running (Phase 4)
- Authelia stack running (Phase 7)

## Deploy

```bash
# 1. Create prerequisite resources (if not already present)
docker network create circuithq-monitoring --internal --attachable 2>/dev/null || true
docker network create circuithq-public --attachable 2>/dev/null || true
docker volume create circuithq-prometheus-data 2>/dev/null || true
docker volume create circuithq-grafana-data 2>/dev/null || true
docker volume create circuithq-uptime-kuma-data 2>/dev/null || true

# 2. Deploy stack
cd stacks/monitoring
docker compose up -d

# 3. Verify all services
docker compose ps
```

## Health Checks

```bash
# Prometheus
curl -s http://localhost:9090/-/healthy

# Grafana
curl -s http://localhost:3000/api/health

# Alertmanager
curl -s http://localhost:9093/-/healthy

# Node Exporter
curl -s http://host.docker.internal:9100/metrics | head -5

# cAdvisor
curl -s http://localhost:8080/healthz

# Blackbox Exporter
curl -s http://localhost:9115/health

# Uptime Kuma
curl -s http://localhost:3001

# Verify targets in Prometheus
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json,sys
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    print(f\"{'🟢' if t['health']=='up' else '🔴'} {t['labels']['job']}: {t['health']}\")
"
```

## Logs

```bash
# View all services
cd stacks/monitoring
docker compose logs --tail=50

# Follow specific service
docker compose logs -f prometheus
docker compose logs -f grafana

# Check for errors
docker compose logs 2>&1 | grep -i error
```

## Common Operations

### Reload Prometheus Config (without restart)

```bash
curl -X POST http://localhost:9090/-/reload
```

### Add a New Scrape Target

1. Edit `stacks/monitoring/prometheus/prometheus.yml`
2. Add new job under `scrape_configs`
3. Reload Prometheus: `curl -X POST http://localhost:9090/-/reload`

### Add a Dashboard in Grafana

```bash
# Export dashboard JSON from Grafana UI
# Place it in stacks/monitoring/grafana/dashboards/
# The provisioning provider picks it up within 60 seconds
```

### Silence an Alert

Via Alertmanager UI at `http://alertmanager:9093` (port-forward or via Tailscale).

### List Active Alerts

```bash
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool | head -50
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|------|
| Prometheus target `DOWN` | Service not on monitoring network | Check network attachment |
| Grafana "Datasource not found" | Prometheus not started first | Restart Grafana after Prometheus |
| Node Exporter no data | Host networking issue | Verify `network_mode: host` and port 9100 |
| cAdvisor "permission denied" | Missing volume mounts | Restart with correct bind mounts |
| Blackbox probe fails | DNS resolution | Check targets are valid hostnames |
| Alertmanager no notifications | Slack/email config incomplete | Update `alertmanager/config.yml` with credentials |
| Grafana login loop | Authelia redirect | Check Grafana is on proxy network and auth-chain is correct |
| Disk full on Prometheus | Retention too long | Reduce `--storage.tsdb.retention.time` to 15d |

## Backup

```bash
# Backup Prometheus data
docker run --rm -v circuithq-prometheus-data:/source -v /backup:/dest alpine tar czf /dest/prometheus-$(date +%Y%m%d).tar.gz -C /source .

# Backup Grafana data
docker run --rm -v circuithq-grafana-data:/source -v /backup:/dest alpine tar czf /dest/grafana-$(date +%Y%m%d).tar.gz -C /source .

# Restore
docker run --rm -v circuithq-prometheus-data:/dest -v /backup:/source alpine tar xzf /source/prometheus-20250101.tar.gz -C /dest
docker compose restart prometheus
```

## Maintenance

### Update Images

```bash
cd stacks/monitoring
docker compose pull
docker compose up -d
```

### Rebuild Prometheus TSDB (clean start)

```bash
docker compose down prometheus
docker run --rm -v circuithq-prometheus-data:/data alpine rm -rf /data/*
docker compose up -d prometheus
```

### Grafana Admin Password Reset

```bash
docker exec -it circuithq-grafana grafana-cli admin reset-admin-password newpassword
```

## Rollback

```bash
cd stacks/monitoring
docker compose down
git checkout HEAD~1 -- stacks/monitoring/
docker compose up -d
```