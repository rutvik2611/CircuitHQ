# CircuitHQ — Homelab Platform

A production-grade, single-node homelab platform built on free and open-source software. Designed for stability, security, observability, and easy expansion.

## Architecture

```
Internet → Cloudflare DNS → Cloudflare Tunnel → Traefik → Services
                                               
Admin → Tailscale (private mesh) → Host SSH / Private Dashboards
```

- **Public ingress:** Cloudflare Tunnel → Traefik reverse proxy (no exposed router ports)
- **Private admin:** Tailscale with MagicDNS, ACLs, and optional SSH
- **Runtime:** Docker Compose on a single node (M3 Mac / PiKVM)
- **Secrets:** SOPS + age — encrypted in Git, decrypted only on the target host
- **Observability:** Prometheus + Grafana + Loki + Alertmanager
- **Backups:** restic with encrypted local/NAS targets and automated restore testing
- **Delivery:** GitOps-inspired — Git is source of truth, CI validates, manual deploy approval

## Tech Stack

| Layer | Tool |
|-------|------|
| Runtime | Docker CE + Compose |
| Reverse proxy | Traefik |
| Public edge | Cloudflare DNS + Cloudflare Tunnel |
| Private access | Tailscale |
| Secrets | SOPS + age |
| Monitoring | Prometheus, Grafana, Node Exporter, cAdvisor, Alertmanager |
| Logging | Loki + Promtail |
| Backups | restic |
| Auth | Authelia |
| CI | GitHub Actions (self-hosted M3 Mac runner) |
| Security | Trivy, Syft, gitleaks |

## Repository Structure

```
├── docs/           Architecture, runbooks, ADRs, diagrams, troubleshooting
├── infra/          Host, Tailscale, Cloudflare, security configs
├── compose/        Top-level Compose entrypoints and shared definitions
├── stacks/         Modular service stacks (proxy, auth, monitoring, etc.)
├── configs/        Environment-specific non-secret configuration
├── secrets/        SOPS-encrypted secret files (never plaintext)
├── scripts/        Bootstrap, deploy, validate, backup, maintenance
├── ci/             CI workflow definitions and helper scripts
├── templates/      Reusable templates for services, docs, Traefik
├── tests/          Automated validation scripts
└── releases/       Generated release metadata
```

## Quickstart

```bash
# Prerequisites: Docker + Docker Compose
make validate         # Run all local validation checks
make lint             # YAML, shell, Markdown linting
make compose-config   # Validate Compose configs
make integration-test # Start test stack and verify health
```

## Reading Order

1. `docs/architecture/overview.md` — Big picture
2. `docs/architecture/network.md` — Network design
3. `docs/architecture/security.md` — Security model
4. `docs/runbooks/` — Operational procedures
5. `docs/decisions/` — Architecture Decision Records

## Principles

- Free software where possible
- No exposed router ports — Cloudflare Tunnel for public access
- Least-privilege everywhere: networks, containers, users, ACLs
- Secrets encrypted at rest in Git via SOPS + age
- Every change validated locally and in CI
- Production deploys require manual approval
- Self-documenting — the repo tells you everything

License: MIT