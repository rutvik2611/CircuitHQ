# Logging Architecture — Loki + Promtail

## Overview

CircuitHQ uses **Loki** for centralized log storage and **Promtail** for log collection. Logs are ingested from Docker containers and Traefik, labeled by container metadata, and queried from Grafana.

```
Docker Containers
       │
       │ /var/lib/docker/containers/*/*-json.log
       ▼
┌────────────┐
│  Promtail   │  (label with container_id, container_name, image)
└─────┬──────┘
      │ HTTP POST (push)
      ▼
┌────────────┐
│   Loki     │  (TSDB-based storage, compressed chunks)
└─────┬──────┘
      │
      ▼
┌────────────┐
│  Grafana   │  (Explore / Dashboards)
└────────────┘
```

## Components

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| **Loki** | `grafana/loki:3.4` | 3100 | Log storage, indexing, query |
| **Promtail** | `grafana/promtail:3.4` | 9080 | Log collection, labeling, shipping |

Both run on the `circuithq-monitoring` internal network only.

## Log Sources

| Source | Method | Labels | Retention |
|--------|--------|--------|-----------|
| **All Docker containers** | Read JSON logs from `/var/lib/docker/containers/` | `job=docker`, `container_name`, `container_image` | 14 days |
| **Traefik access logs** | Read `/var/log/traefik/access.log` | `job=traefik`, `ServiceName`, `RouterName`, `StatusCode` | 30 days |
| **System logs** (optional) | systemd journal | `job=system` | 7 days |

## Retention Strategy

Retention is tuned for homelab SSD constraints:

| Stream | Retention | Storage Type | Notes |
|--------|-----------|-------------|-------|
| Docker container logs | 14 days | Compressed chunks | Highest volume |
| Traefik access logs | 30 days | Compressed chunks | Low volume, useful for audit |
| System logs | 7 days | Compressed chunks | Lowest priority |
| Index cache | 7 days | TSDB | Speeds up recent queries |
| Query lookback limit | 30 days | — | Hard limit on query window |

All chunks are stored on the `circuithq-loki-data` volume. The compactor enforces retention and deletes expired data after a 2-hour safety delay.

## Performance Targets

| Metric | Target |
|--------|--------|
| Ingestion rate | ≤ 10 MB/s |
| Ingestion burst | ≤ 20 MB/s |
| Max query series | 5,000 |
| Concurrent queries | ≤ 8 |
| Per-stream retention | Configurable per job |

## Grafana Integration

- Loki datasource is auto-provisioned in Grafana (set as *default* datasource)
- Prometheus remains available as a secondary datasource for metrics-to-logs correlation
- Use Grafana **Explore** with Loki to query logs with LogQL

### Example LogQL Queries

```logql
# All logs from a specific container
{container_name="circuithq-traefik"}

# Errors from any container
{job="docker"} |= "error"

# Traefik 5xx errors
{job="traefik"} | StatusCode=~"5.."

# Rate of errors per container (last 1h)
rate({job="docker"} |= "error"[1h])

# Top 5 containers by log volume (last 24h)
topk(5, sum by(container_name) (count_over_time({job="docker"}[24h])))
```

## Log Rotation (Docker Daemon)

Docker daemon log rotation is configured globally in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Each service in the monitoring/compose.yml also sets per-container log limits to prevent runaway logs from filling disk.

## Sensitive Data Handling

1. **Log content:** Promtail does not drop or mask log content by default. Sensitive fields (passwords, tokens, secrets) should be redacted at the application level.
2. **Traefik access logs:** `Authorization`, `Cookie`, and `ClientUsername` headers are dropped by Traefik's `accessLog.fields.names` configuration.
3. **Container environment variables:** Environment variables are not included in Docker log output. If needed, they must be logged explicitly by the application.
4. **Loki retention:** Expired data is deleted by the compactor. Do not rely on deletion for compliance — configure application-level masking instead.
5. **Audit:** Traefik logs are retained 30 days for access audit. No PII is expected in CircuitHQ logs.

## Network

| Network | Services | Purpose |
|---------|----------|---------|
| `circuithq-monitoring` | Loki, Promtail | Internal log pipeline (no external exposure) |

Loki and Promtail are **not** exposed via Traefik. Query logs via Grafana's Loki datasource (Grafana is behind Authelia).

## Directory Structure

```
stacks/logging/
├── compose.yml              # Loki + Promtail services
├── loki/
│   └── config.yml           # Loki config with retention, compactor, limits
└── promtail/
    └── config.yml           # Promtail scrape configs, Docker + Traefik
```