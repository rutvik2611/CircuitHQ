# CircuitHQ Documentation

The documentation is organized into four sections, matching the reading order in the root `README.md`.

## Section 1: Architecture

| Document | Description |
|----------|-------------|
| [Architecture Overview](architecture/overview.md) | Big picture — platform design, traffic flow, component map |
| [Network Architecture](architecture/network.md) | Docker network layout, segmentation, forbidden paths |
| [Traefik Architecture](architecture/traefik.md) | Reverse proxy, TLS, ACME, middleware chains, entrypoints |
| [Authentication Architecture](architecture/authentication.md) | Authelia + ForwardAuth, MFA, RBAC, session flow |
| [Monitoring Architecture](architecture/monitoring.md) | Prometheus, Grafana, Alertmanager, Node Exporter, cAdvisor, Blackbox, Uptime Kuma |
| [Logging Architecture](architecture/logging.md) | Loki + Promtail, retention strategies, LogQL examples |
| [Backup Architecture](architecture/backups.md) | restic snapshots, encryption, retention policy, restore testing |
| [Security Architecture](architecture/security.md) | Layered defense, compose security, permission validation, CI scanning |
| [Tailscale Architecture](architecture/tailscale.md) | Private admin mesh, MagicDNS, Tailscale SSH, ACL model |

## Section 2: Runbooks

| Document | Description |
|----------|-------------|
| [Host Bootstrap](runbooks/host-bootstrap.md) | Prepare a macOS host from scratch |
| [Traefik Runbook](runbooks/traefik.md) | Deploy, health check, add services, cert management |
| [Cloudflare Tunnel Runbook](runbooks/cloudflared.md) | Deploy, ingress rules, tunnel token, metrics |
| [Authentication Runbook](runbooks/authentication.md) | Deploy, add users, reset passwords, MFA recovery |
| [Secrets Runbook](runbooks/secrets.md) | SOPS + age setup, daily ops, key rotation |
| [Deployment Runbook](runbooks/deploy.md) | Deploy workflow, single-stack, CI deploy, rollback |
| [Monitoring Runbook](runbooks/monitoring.md) | Deploy, health checks, alerts, maintenance |
| [Logging Runbook](runbooks/logging.md) | Deploy, queries, custom sources, retention tuning |
| [Backup Runbook](runbooks/backup.md) | Setup, manual backup, integrity checks, monitoring |
| [Restore Runbook](runbooks/restore.md) | Snapshot restore, full DR, volume recovery, database restore |
| [Tailscale Recovery](runbooks/tailscale-recovery.md) | Service down, auth expired, ACL lockout, fallback SSH |
| [Security Incident Response](runbooks/security.md) | Incident detection, breach containment, recovery |

## Section 3: Architecture Decision Records

| Document | Description |
|----------|-------------|
| [ADR-0001: Platform Principles](decisions/ADR-0001-platform-principles.md) | Core architectural principles (FOSS, least-privilege, Git as source of truth) |
| [ADR-0002: CI/CD Strategy](decisions/ADR-0002-cicd-strategy.md) | CI system selection, self-hosted runner setup, approval gates |

## Section 4: Troubleshooting

| Document | Description |
|----------|-------------|
| [Troubleshooting Index](troubleshooting/README.md) | Common issues organized by component |

## Section 5: Diagrams

| Document | Description |
|----------|-------------|
| [Diagrams Index](diagrams/README.md) | Text-based network and traffic flow diagrams |

## Supporting Files

| File | Description |
|------|-------------|
| [ci/README.md](../ci/README.md) | CI/CD comparison, runner setup, workflow docs |
| [secrets/README.md](../secrets/README.md) | Secret inventory, key custody, rotation |
| [releases/README.md](../releases/README.md) | Release metadata format, rollback reference |
| [CHANGELOG.md](../CHANGELOG.md) | Project changelog by phase |