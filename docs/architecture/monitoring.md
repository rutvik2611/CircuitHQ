# Monitoring Architecture

## Overview

CircuitHQ uses a **Prometheus + Grafana + Alertmanager** stack for metrics collection, visualization, and alerting. Node Exporter, cAdvisor, and Blackbox Exporter provide system, container, and external health data.

```
                    ┌──────────────┐
                    │  Traefik      │
                    │  (metrics)    │
                    └──────┬───────┘
                           │ :8080
                    ┌──────┴───────┐
                    │  Prometheus   │
                    │  (scraper)    │
                    └──────┬───────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
   ┌──────┴──────┐ ┌──────┴──────┐ ┌───────┴──────┐
   │ Alertmanager│ │   Grafana   │ │  Blackbox    │
   │ (alerts)    │ │ (dashboards)│ │  Exporter    │
   └─────────────┘ └─────────────┘ └──────────────┘
```

## Components

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| **Prometheus** | `prom/prometheus:v3.2` | 9090 | Metrics collection and alert evaluation |
| **Grafana** | `grafana/grafana:11.6-oss` | 3000 | Dashboards and visualization |
| **Alertmanager** | `prom/alertmanager:v0.28` | 9093 | Alert deduplication, routing, notifications |
| **Node Exporter** | `prom/node-exporter:v1.9` | 9100 | Host-level metrics (CPU, memory, disk, network) |
| **cAdvisor** | `gcr.io/cadvisor/cadvisor:v0.52` | 8080 | Container-level metrics |
| **Blackbox Exporter** | `prom/blackbox-exporter:v0.26` | 9115 | External health checks (HTTP, ICMP, TCP) |
| **Uptime Kuma** | `louislam/uptime-kuma:1.23` | 3001 | Public status page |

## Networks

| Network | Purpose | Services |
|---------|---------|----------|
| `circuithq-monitoring` | Internal metrics plane (all monitoring traffic) | All components |
| `circuithq-proxy` | Traefik routing for web UIs | Grafana, Uptime Kuma |
| `circuithq-public` | Public status page | Uptime Kuma |

Node Exporter uses `network_mode: host` to access real host network and filesystem metrics.

## Data Retention

| Data | Retention | Storage |
|------|-----------|---------|
| Prometheus TSDB | 30 days | `circuithq-prometheus-data` volume |
| Grafana data | Indefinite | `circuithq-grafana-data` volume |

## Alert Rules

| Rule Group | Alerts | Severity |
|-----------|--------|----------|
| **Host** | CPU > 80%, Memory > 85%, Disk < 10%, OOM kills | Warning → Critical |
| **Container** | Down, CPU > 80%, Memory > 85%, Frequent restarts | Warning → Critical |
| **Traefik** | 5xx > 5%, 4xx > 20%, No traffic, High latency | Warning → Critical |
| **Backup** | Stale backup > 48h, Recent failures | Critical |
| **Certificate** | Expires < 30d, < 7d, expired | Warning → Critical |

## Alert Routing

- **Critical alerts:** Slack + Email (`admin@circuithq.internal`)
- **Warning alerts:** Slack only

See `stacks/monitoring/alertmanager/config.yml` for full routing config.

## Scrape Targets

| Job | Target | Interval | Purpose |
|-----|--------|----------|---------|
| `prometheus` | localhost:9090 | 30s | Prometheus self-metrics |
| `node` | host.docker.internal:9100 | 30s | Host CPU, memory, disk, network |
| `cadvisor` | cadvisor:8080 | 30s | Container resource usage |
| `traefik` | traefik:8080 | 30s | Request rates, latency, status codes |
| `authelia` | authelia:9959 | 30s | Auth request metrics |
| `cloudflared` | cloudflared:2000 | 30s | Tunnel health metrics |
| `blackbox-http` | External URLs via blackbox:9115 | 30s | HTTP health + TLS cert expiry |
| `blackbox-icmp` | External IPs via blackbox:9115 | 30s | Internet connectivity |

## Grafana

- **Authelia-protected** (`auth-chain` middleware)
- URL: `https://grafana.circuithq.internal`
- Admin user: `admin` (password via SOPS secret)
- Provisions Prometheus datasource automatically on startup
- Dashboards provisioned from `grafana/dashboards/` directory

## Uptime Kuma

- **Public** status page (bypasses Authelia — `public-chain` middleware)
- URL: `https://status.circuithq.internal`
- Monitors: Traefik, Grafana, Authelia, external endpoints
- Separate monitoring network for internal probes

## Directory Structure

```
stacks/monitoring/
├── compose.yml                         # All monitoring services
├── prometheus/
│   ├── prometheus.yml                  # Scrape configuration
│   └── rules/
│       ├── host.yml                    # Host alert rules
│       ├── container.yml               # Container alert rules
│       ├── traefik.yml                 # Traefik alert rules
│       ├── backup.yml                  # Backup alert rules
│       └── certificate.yml             # Certificate alert rules
├── grafana/
│   ├── datasources/datasources.yml     # Prometheus datasource
│   └── dashboards/dashboards.yml       # Dashboard provisioning
├── alertmanager/
│   └── config.yml                      # Alert routing and notifications
└── blackbox/
    └── modules.yml                     # HTTP, ICMP, TCP probe config
```