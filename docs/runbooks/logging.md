# Logging Stack Runbook

## Prerequisites

- Docker and Docker Compose installed
- Network exists: `circuithq-monitoring`
- Volume exists: `circuithq-loki-data`
- Monitoring stack running (Phase 8) — Grafana needed for log queries

## Deploy

```bash
# 1. Create prerequisite resources (if not already present)
docker network create circuithq-monitoring --internal --attachable 2>/dev/null || true
docker volume create circuithq-loki-data 2>/dev/null || true

# 2. Start the logging stack
cd stacks/logging
docker compose up -d

# 3. Verify
docker compose ps
docker compose logs --tail=20
```

## Health Check

```bash
# Loki readiness
curl -s http://localhost:3100/ready

# Loki metrics
curl -s http://localhost:3100/metrics | grep -E "loki_ingester|loki_distributor"

# Promtail readiness (metrics port)
curl -s http://localhost:9080/metrics | grep promtail

# Check Promtail is writing to Loki
curl -s http://localhost:3100/loki/api/v1/tail | head -1
```

## Query Logs in Grafana

1. Open Grafana: `https://grafana.circuithq.internal`
2. Go to **Explore** (left menu)
3. Select the **Loki** datasource
4. Run a query:

```logql
# Recent logs from Traefik
{job="traefik"} |= ``

# Errors from any container in last 30 minutes
{job="docker"} |= "error" |= `` != "healthcheck"
```

## Logs (Docker CLI)

```bash
# Follow all logging stack logs
cd stacks/logging
docker compose logs -f

# Loki logs
docker compose logs loki --tail=50

# Promtail logs
docker compose logs promtail --tail=50

# Check if Promtail is forwarding logs
docker compose logs promtail 2>&1 | grep -E "received|sent|position"
```

## Common Operations

### Check Loki Storage Usage

```bash
# Check volume size
docker run --rm -v circuithq-loki-data:/data alpine du -sh /data

# Query for total log volume by job
curl -s 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query=sum by (job) (bytes_over_time({job=~"docker|traefik"}[1h]))'
```

### Reload Promtail Config

```bash
# Promtail picks up config changes on SIGHUP or restart
docker compose -f stacks/logging/compose.yml restart promtail
```

### Change Retention Period

1. Edit `stacks/logging/loki/config.yml` — update `retention_streams` periods
2. Restart Loki:

```bash
docker compose -f stacks/logging/compose.yml restart loki
```

### Add a Custom Log Source

1. Add a new `scrape_config` entry in `stacks/logging/promtail/config.yml`
2. Ensure the log file is mounted as a bind volume in `compose.yml`
3. Restart Promtail

### Check for Missing Logs

```bash
# Check Loki for ingested logs (last hour)
curl -s 'http://localhost:3100/loki/api/v1/labels' | python3 -m json.tool

# Check if a specific container's logs are present
curl -s 'http://localhost:3100/loki/api/v1/label/container_name/values' | python3 -m json.tool

# Query count of log lines by container
curl -s 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query=count_over_time({job="docker"}[5m])' \
  --data-urlencode 'start='$(date -v-5M +%s)'000000000' \
  --data-urlencode 'end='$(date +%s)'000000000' \
  --data-urlencode 'step=300' | python3 -m json.tool
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|------|
| No logs in Grafana | Promtail → Loki connection | `docker compose logs promtail` — check `clients.url` |
| `Loki refused connection` | Loki not ready | Check `docker compose logs loki` for startup errors |
| Logs missing for one container | Container not in Docker socket path | Promtail reads `/var/lib/docker/containers/*/*-json.log` |
| `Position file error` | Promtail position file corrupt | `docker compose restart promtail` (regenerates) |
| Disk growing too fast | Retention too long | Shorten `retention_period` in Loki config |
| High memory usage | Too many labels | Reduce `max_query_series` and check cardinality |
| `Ingestion rate limit exceeded` | Too many logs too fast | Tune Docker log `max-size` smaller |
| Timestamps wrong in logs | Timezone mismatch | Set `TZ` env var in both services |

## Docker Log Rotation

Configured globally in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Per-container overrides are set in each compose.yml under `logging:`.

**To apply global changes:**

```bash
sudo systemctl restart docker   # Drains all containers briefly
```

## Sensitive Data Handling

| Data Type | Handling | Location |
|-----------|----------|----------|
| HTTP Authorization headers | Dropped by Traefik access log config | `traefik/static.yml` |
| Client usernames | Dropped by Traefik access log config | `traefik/static.yml` |
| Application secrets | Must be redacted at application level | Application code |
| Environment variables | Not included in Docker log output | N/A |
| Tokens in query strings | Visible if logged — redact at app level | Application code |

## Maintenance

### Update Images

```bash
cd stacks/logging
docker compose pull
docker compose up -d
```

### Compact Loki Data Manually

```bash
# Trigger compactor via API (requires auth disabled in dev)
curl -X POST http://localhost:3100/compactor/trigger
```

## Rollback

```bash
cd stacks/logging
docker compose down
git checkout HEAD~1 -- stacks/logging/
docker compose up -d
```