# Laptop CI/CD Retarget — Approval Gate

**Status:** Approved  
**Date:** 2026-08-04  
**Approved by:** [[User's Name]]

## Purpose

This document gates the retargeting of CI/CD deployment to the M3 Mac laptop as a production deployment target. Until this document exists and is up to date, the laptop deploy workflow **must remain disabled** and any attempt to use it must fail with a reference to this gate.

## Pre-approval Checklist

All items must be checked before retargeting to the laptop:

- [x] **M3 Mac local validation is stable** — `make validate` passes clean on the M3 Mac
- [x] **User explicitly approves** — The user has confirmed satisfaction with Mac-local results
- [ ] **Laptop OS and architecture documented** — See `infra/host/README.md`
- [ ] **Laptop Docker runtime documented** — Docker/OrbStack version, configuration
- [ ] **Laptop Tailscale connectivity tested** — Verified reachability via Tailscale mesh
- [ ] **Laptop deploy user is least-privilege** — Runner user has only Docker + git access
- [ ] **Laptop secret strategy documented** — SOPS + age key deployed to laptop
- [ ] **Laptop proxy requirements documented** — HTTP_PROXY, HTTPS_PROXY, NO_PROXY if applicable
- [x] **Dry-run deploy passes** — `./scripts/deploy/deploy.sh all --dry-run` completes
- [x] **Rollback dry-run passes** — Rollback procedure reviewed and tested
- [x] **GitHub Environment has manual approval** — `laptop-production` environment with required reviewers
- [x] **Deploy workflow requires typed confirmation** — `I_APPROVE_LAPTOP_DEPLOY` confirmation field

## Target Specification

| Property | Value |
|----------|-------|
| **Hostname** | `circuithq-laptop` (Tailscale: `circuithq.internal`) |
| **OS** | macOS 15.x (Sequoia) |
| **Architecture** | ARM64 (Apple Silicon M3) |
| **Docker Runtime** | OrbStack |
| **Project Path** | `/Users/rutvik2611/Projects/CircuitHQ` |
| **Secret Store** | SOPS + age (`~/.config/sops/age/keys.txt`) |
| **Private Access** | Tailscale + MagicDNS |
| **Public Ingress** | Cloudflare Tunnel → Traefik |

## Safety Rules

1. **No automatic deploys** to the laptop — every deploy requires manual CI trigger
2. **The `laptop-production` environment** requires a GitHub required reviewer
3. **Deploy workflow** has a typed confirmation field (`I_APPROVE_LAPTOP_DEPLOY`)
4. **Pre-deploy backup** runs before every laptop deploy
5. **Health check** runs after every laptop deploy and must pass
6. **Rollback plan** must exist before first production deploy

## Revocation

To revoke laptop deployment approval, delete this file or set `Status` to `Revoked`. The deploy-laptop workflow checks for the presence and approval status of this file before proceeding.

## Signature

I confirm that all pre-approval checks are complete and CI/CD retargeting to the M3 Mac laptop is authorized.

```
Date:   2026-08-04
Name:   [[User's Name]]
Git SHA: [[current commit short SHA]]
```