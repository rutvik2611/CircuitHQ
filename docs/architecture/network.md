# Network Architecture

## Overview

CircuitHQ uses purpose-built Docker networks for least-privilege container communication.
Each service attaches only to the networks it requires, and no more.

## Network Layout

```
                        +------------------------------------------+
                        |              circuithq-proxy             |
                        |  Traefik ↔ cloudflared ↔ public services |
                        +-------------------+----------------------+
                                            |
         +----------+----------+------------+------------+----------+----------+
         |          |          |            |            |          |          |
         v          v          v            v            v          v          v
  circuithq   circuithq  circuithq    circuithq    circuithq   circuithq  circuithq
  -public      -private  -management  -monitoring  -database   -shared    -backup
  (apps)     (admin UI)  (portainer)  (prom/grf)   (DB only)   (svc-svc)  (restic)
```

## Network Descriptions

| Network | Internal | Purpose | Attached Services |
|---------|----------|---------|-------------------|
| `circuithq-proxy` | No | Traefik ↔ cloudflared ↔ public services | Traefik, cloudflared, public web apps |
| `circuithq-public` | No | Public apps behind Traefik | Public web apps, APIs |
| `circuithq-private` | Yes | Private/admin-only services | Grafana, Portainer, private APIs |
| `circuithq-management` | Yes | Mgmt tools | Portainer, management agents |
| `circuithq-monitoring` | Yes | Metrics scraping | Prometheus, Node Exporter, cAdvisor, Grafana, Alertmanager |
| `circuithq-database` | Yes | Database containers only | Postgres, Redis, MariaDB, etc. |
| `circuithq-shared` | No | Service-to-service comms | App services that need to talk to each other |
| `circuithq-backup` | Yes | Backup access to volumes | restic/borg backup containers |
| `circuithq-security` | Yes | Security tools | CrowdSec, fail2ban |

## Forbidden Communication Paths

| From | To | Why |
|------|----|-----|
| Database | proxy | DB must never be reachable from ingress |
| Public app | management | Management tools must not be exposed |
| Monitoring | proxy | Scrapers should not initiate external connections |
| Backup | internet (except target) | Backup should only reach its repository |

## Container-Network Attachment Rules

- Traefik: `proxy`, `monitoring`
- cloudflared: `proxy`
- Public app: `public`, `shared` (if needing internal comms)
- Private app: `private`, `shared`
- Database: `database` only
- Grafana: `private`, `monitoring`
- Prometheus: `monitoring`
- Alertmanager: `monitoring`
- Node Exporter: `monitoring`
- cAdvisor: `monitoring` (host-level access via volume mount)
- restic: `backup` (volume mounts for data access)
- Authelia: `shared`, `database` (if using Redis/DB)
- CrowdSec: `security`, `proxy` (for log parsing)