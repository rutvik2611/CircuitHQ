# CircuitHQ Diagrams

This directory contains text-based network topology and traffic flow diagrams for the CircuitHQ homelab platform. All diagrams use ASCII/Unicode art so they render natively in any terminal or Markdown viewer.

## Available Diagrams

Currently, architecture diagrams are embedded in the respective documentation files:

| Diagram | Location | Format |
|---------|----------|--------|
| Full traffic flow (public + private) | [Architecture Overview](../architecture/overview.md) | ASCII art |
| Network layout | [Network Architecture](../architecture/network.md) | ASCII art |
| Monitoring pipeline | [Monitoring Architecture](../architecture/monitoring.md) | ASCII art |
| Logging pipeline | [Logging Architecture](../architecture/logging.md) | ASCII art |
| Authelia auth flow | [Authentication Architecture](../architecture/authentication.md) | ASCII art |
| Traefik ingress | [Traefik Architecture](../architecture/traefik.md) | ASCII art |
| Backup pipeline | [Backup Architecture](../architecture/backups.md) | ASCII art |
| Security layers | [Security Architecture](../architecture/security.md) | ASCII art |
| Secret flow | [Secrets Runbook](../runbooks/secrets.md) | ASCII art |
| Tailscale modes | [Tailscale Architecture](../architecture/tailscale.md) | ASCII art |

## Network Topology

```
                          ┌─────────────────────────┐
                          │     Internet             │
                          │    (Cloudflare DNS)      │
                          └───────────┬─────────────┘
                                      │
                                      ▼
                          ┌─────────────────────────┐
                          │  Cloudflare Edge         │
                          │  (WAF, DDoS, TLS)        │
                          └───────────┬─────────────┘
                                      │ outbound WebSocket
                                      ▼
                          ┌─────────────────────────┐
                          │  Cloudflare Tunnel       │
                          │  (no open inbound ports) │
                          └───────────┬─────────────┘
                                      │ port 443
                                      ▼
              ┌────────────────────────────────────────┐
              │           circuithq-proxy               │
              │                                         │
              │  ┌──────────────────────────────────┐   │
              │  │         Traefik                   │   │
              │  │  (TLS, routing, auth, headers,    │   │
              │  │   rate limiting, metrics :8080)   │   │
              │  └──────────┬───────────┬───────────┘   │
              │             │           │               │
              └─────────────┼───────────┼───────────────┘
                            │           │
            ┌───────────────┘           └───────────────┐
            ▼                                             ▼
   circuithq-public                                circuithq-private
            │                                             │
            ▼                                             ▼
  ┌──────────────────┐                       ┌──────────────────────┐
  │  Public Apps      │                       │  Private/Admin Apps │
  │  (whoami, status) │                       │  (Grafana, Prom UI) │
  └──────────────────┘                       └──────────────────────┘
```

## Container Layout By Stack

```
                    ┌──────────────── PROXY ────────────────┐
                    │  Traefik (Docker socket, ACME, TLS)   │
                    │  Cloudflared (tunnel conn)            │
                    └────────────┬──────────────────────────┘
                                 │
    ┌────────────────────────────┼────────────────────────────┐
    ▼                            ▼                            ▼
┌─────────── AUTH ─────────┐ ┌──── MONITORING ───────┐ ┌─── LOGGING ──┐
│  Authelia (forward-auth) │ │  Prometheus (scrape)   │ │  Loki (store)│
│  Redis (session store)   │ │  Grafana (dashboards)  │ │  Promtail    │
└──────────────────────────┘ │  Alertmanager (alerts) │ │  (collector) │
                             │  Node Exporter (host)  │ └──────────────┘
                             │  cAdvisor (containers) │
                             │  Blackbox (external)   │
                             │  Uptime Kuma (status)  │
                             └────────────────────────┘

                    ┌─────────── APPS ───────────────┐
                    │  Example Public App (whoami)    │
                    │  Example Private App (nginx)    │
                    └────────────────────────────────┘
```

## Future Diagrams

To add a new diagram to this directory:

1. Create a `.md` file with a clear ASCII/Unicode diagram
2. Include a legend for any symbols used
3. Reference it from the relevant architecture doc or runbook
4. Add it to the table above