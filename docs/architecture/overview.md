# Architecture Overview

## What is CircuitHQ?

CircuitHQ is a **production-grade, single-node homelab platform** built entirely on free and open-source software. It runs on a single M-series Mac (or any Linux host) and provides a secure, observable, and maintainable foundation for self-hosted services.

## Design Philosophy

| Principle | Why |
|-----------|-----|
| **No exposed ports** | All public ingress goes through Cloudflare Tunnel. No firewall ports 80/443 open. |
| **Least privilege** | Containers get only the capabilities, networks, and volumes they need. |
| **Secrets encrypted in Git** | SOPS + age ensures no plaintext secrets anywhere. |
| **Self-documenting** | The repo alone can teach a new admin how to operate the platform. |
| **Validated everywhere** | Same checks run locally (`make validate`) and in CI. |
| **ARM64-native** | All images support Apple Silicon. No emulation layer. |

## Traffic Flow (Public)

```
User Browser
      │
      ▼
Cloudflare DNS  ──→  Cloudflare Edge (WAF, DDoS, TLS)
                              │
                              ▼
                    Cloudflare Tunnel (outbound WebSocket)
                              │
                              ▼
                    ┌──────────────────┐
                    │    Traefik        │
                    │  (TLS, routing,   │
                    │   auth, headers,  │    ┌────────────┐
                    │   rate limiting)  │◄───│  Authelia  │
                    └────────┬─────────┘    │  (forward  │
                             │              │    auth)   │
                ┌────────────┼────────────┐ └────────────┘
                ▼            ▼            ▼
          ┌─────────┐ ┌─────────┐ ┌─────────┐
          │  App A  │ │  App B  │ │  App C  │
          │ (public)│ │(private)│ │ (admin) │
          └─────────┘ └─────────┘ └─────────┘
```

- **Public apps** (bypass auth): status.circuithq.internal
- **Private apps** (one-factor auth): *.app.circuithq.internal
- **Admin dashboards** (two-factor auth): traefik, grafana, prometheus

## Traffic Flow (Private Admin)

```
Admin Device ──Tailscale mesh (WireGuard)──→ CircuitHQ Host
                                                   │
                                        SSH (Tailscale SSH)
                                        Grafana (port 3000)
                                        Prometheus (port 9090)
                                        Traefik dashboard
```

Tailscale is the **private admin plane**. All dashboards are accessible without Cloudflare tunnel.

## Component Map

```
┌──────────────────────────────────────────────────────────┐
│                     STACKS                                │
│                                                          │
│  PROXY           AUTH          MONITORING      LOGGING   │
│  ┌────────┐  ┌──────────┐  ┌──────────────┐ ┌────────┐ │
│  │ Traefik│  │ Authelia │  │ Prometheus   │ │ Loki   │ │
│  │Cloudflr│  │ Redis    │  │ Grafana      │ │Promtail│ │
│  └────────┘  └──────────┘  │ Alertmanager │ └────────┘ │
│                            │ Node Exp     │            │
│            APPS            │ cAdvisor     │            │
│  ┌──────────────────┐      │ Blackbox     │            │
│  │ Example Public   │      │ Uptime Kuma  │            │
│  │ Example Private  │      └──────────────┘            │
│  └──────────────────┘                                   │
│                                                          │
│  ...more apps as needed                                  │
└──────────────────────────────────────────────────────────┘
```

## Networks

9 purpose-built Docker networks enforce container isolation:

| Network | Traffic | Purpose |
|---------|---------|---------|
| `circuithq-proxy` | Traefik ↔ upstream services | Ingress routing |
| `circuithq-public` | Public app traffic | App-level networking |
| `circuithq-private` | Private/admin traffic | Internal dashboards |
| `circuithq-monitoring` | Metrics & logs | Prom scraping, log shipping |
| `circuithq-database` | Database only | DB isolation |
| `circuithq-security` | Auth services | Authelia ↔ Redis |
| `circuithq-backup` | Backup containers | restic volume access |
| `circuithq-management` | Management tools | Portainer etc. |
| `circuithq-shared` | Service-to-service | Inter-app communication |

## Volumes

| Volume | Contains | Stacks |
|--------|----------|--------|
| `circuithq-traefik-acme` | Let's Encrypt certificates | proxy |
| `circuithq-redis-data` | Authelia sessions | auth |
| `circuithq-prometheus-data` | 30-day metrics TSDB | monitoring |
| `circuithq-grafana-data` | Dashboards, config | monitoring |
| `circuithq-uptime-kuma-data` | Status page config | monitoring |
| `circuithq-loki-data` | Log chunks, indexes | logging |

## Secret Flow

```
Editor ──→ sops --encrypt ──→ secrets/*.sops.yaml (committed)
                                              │
                                    sops --decrypt
                                              │
                                              ▼
                                   .secrets-rendered/*.env (0600, gitignored)
                                              │
                                              ▼
                                   Docker Compose env_file:
```

## Deployment Flow

```
Git Push ──→ CI Validate (lint, compose, security, secrets)
              │
              │ (manual approval)
              ▼
        Deploy Script
        1. Preflight (disk, Docker, networks)
        2. Backup (restic)
        3. Render secrets
        4. Pull images
        5. Deploy stacks (up -d)
        6. Health check (all containers)
        7. Verify traffic (end-to-end)
        8. Capture release metadata
```

## Reading Order

For a new admin:

1. **This overview** — big picture
2. [Network Architecture](network.md) — how containers talk to each other
3. [Security Architecture](security.md) — defense in depth
4. [Authentication Architecture](authentication.md) — who gets access to what
5. [Traefik Architecture](traefik.md) — how requests get routed
6. [Monitoring Architecture](monitoring.md) — how health is tracked
7. [Logging Architecture](logging.md) — how logs are collected
8. [Backup Architecture](backups.md) — how data survives
9. **Runbooks** — operational procedures
10. **ADRs** — why decisions were made

## Related

- [ADR-0001: Platform Principles](../decisions/ADR-0001-platform-principles.md)
- [infra/security/README.md](../../infra/security/README.md)
- [Host Bootstrap Runbook](../runbooks/host-bootstrap.md)