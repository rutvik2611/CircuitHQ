# ADR-0001: Platform Architecture Principles

**Status:** Accepted  
**Date:** 2026-08-04  
**Author:** CircuitHQ Team  
**Deciders:** CircuitHQ Team  

## Context

We are building a production-grade homelab platform starting on a single machine (M3 Mac). The platform must be stable, secure, maintainable, observable, and expandable without redesign. We need clear principles to guide all technical decisions.

## Decision

We adopt the following non-negotiable principles:

| # | Principle | Rationale |
|---|-----------|-----------|
| 1 | **Free software where possible** | Avoid vendor lock-in and licensing costs. Docker CE, Traefik, Prometheus, Grafana OSS, Loki, restic, SOPS, age are our defaults. |
| 2 | **No exposed router ports** | All public ingress goes through Cloudflare Tunnel → Traefik. No direct inbound firewall ports. |
| 3 | **Least privilege everywhere** | Containers: non-root, dropped capabilities, read-only FS where compatible. Networks: purpose-isolated, databases never on ingress. Users: admin vs CI vs app. Secrets: encrypted in Git, decrypted only on target. |
| 4 | **Secrets encrypted in Git** | All secrets use SOPS + age. No plaintext `.env.production` or unencrypted credentials are committed. |
| 5 | **Every change validated** | Local `make validate` must pass before commit. CI runs the same checks on PR. Red CI blocks merge. |
| 6 | **Production deploys require manual approval** | No automatic production deploys. Manual approval gate with typed confirmation required. |
| 7 | **Git is source of truth** | All config, docs, and infrastructure definitions live in the repo. Manual drift is forbidden. |
| 8 | **Self-documenting** | Architecture docs, runbooks, ADRs, and service READMEs live with the code. A new admin can understand and recover the platform from docs alone. |
| 9 | **Modular and expandable** | One stack folder per service domain. Network conventions transferable to multi-node or orchestrator (Nomad/Kubernetes) later. |
| 10 | **ARM64-native** | All images support ARM64. No emulation layer. M3 Mac is both dev and eventual deployment target. |

## Consequences

- Cloudflare DNS and Tunnel are the public edge. To reduce lock-in, Traefik remains the real ingress controller and tunnel config is versioned without secrets.
- Tailscale is the private admin plane, not public ingress.
- Docker Compose is the runtime for now; labels and network conventions are forward-compatible with Swarm/Nomad/Kubernetes.
- No paid SaaS is required — self-hosted CI (Forgejo/Woodpecker) is the long-term target; GitHub Actions is the starter.

## Compliance

All future ADRs, infrastructure decisions, and service additions must be consistent with these principles. Exceptions require a documented justification and a new ADR amending this one.

## References

- [Homelab Platform Blueprint](../architecture/overview.md)
- [Network Architecture](../architecture/network.md)
- [Security Architecture](../architecture/security.md)