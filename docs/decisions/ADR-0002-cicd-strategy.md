# ADR-0002: CI/CD Strategy

**Status:** Accepted  
**Date:** 2026-08-04  
**Author:** CircuitHQ Team  
**Deciders:** CircuitHQ Team  

## Context

CircuitHQ needs automated validation of every change and a repeatable deployment process. We must choose a CI/CD system that balances simplicity, cost, and self-hosting ambition.

The platform is currently hosted on GitHub. Long-term, we plan to self-host on a Gitea/Forgejo instance.

## Decision

We adopt a **layered CI/CD strategy** with two systems running concurrently:

### Layer 1: GitHub Actions (Current)

The primary CI system while the repo is on GitHub.

| Workflow | Trigger | Actions |
|----------|---------|---------|
| `validate.yml` | Push to any branch, PR to main | yamllint, shellcheck, compose config, secrets check, Trivy scan, Syft SBOM |
| `deploy.yml` | Manual (`workflow_dispatch`) | Preflight, backup, render-secrets, pull, up, healthcheck, verify-traffic |

**Key decisions:**
- Validation runs **on push** — catch errors as early as possible
- Deploy requires **manual approval** via `confirm: DEPLOY` field — no automatic deploys
- Deploy workflow runs **only on the self-hosted runner** (M3 Mac) — keeps deploy credentials on local hardware
- Self-hosted runner is the single deploy target; CI cannot deploy to a host it can't reach

### Layer 2: Woodpecker CI (Future)

Skeleton at `.woodpecker.yml` — ready to activate when we switch to self-hosted Gitea.

**Benefits:**
- Drop-in YAML compatible with GitHub Actions syntax for simple pipelines
- Runs on self-hosted infrastructure (no GitHub dependency for CI)
- Same validation logic, different runner

### Layer 3: Local Validation

`make validate` runs the **same checks** as CI. This ensures:
- Developers catch errors before push
- CI failures are never a surprise
- Air-gapped or offline work is validated

## Consequences

### Positive

1. **Zero CI cost** while on GitHub (public repo = unlimited minutes)
2. **Instant validation feedback** via GitHub checks UI on every PR
3. **Deploy credentials never leave local hardware** — runner has access to the age private key and Docker socket
4. **Same checks locally and in CI** — no "works on my machine" gap
5. **Woodpecker skeleton ready** — zero migration work for self-hosted switch

### Negative

1. **Dual CI maintenance** — GitHub Actions and Woodpecker configs need to stay in sync during the transition
2. **Self-hosted runner dependency** — if the M3 Mac is offline, deploy workflow is blocked
3. **No CI on push to non-GitHub remotes** — until Woodpecker is activated, CI only runs on GitHub pushes

### Mitigations

| Risk | Mitigation |
|------|------------|
| Dual CI drift | Woodpecker config is commented out and mirrored to `.woodpecker.yml`; activate only when self-hosting |
| Runner offline | Deploy script can run locally (`./scripts/deploy/deploy.sh all`) without CI |
| Non-GitHub pushes not validated | `make validate` runs locally; add a git pre-push hook if desired |

## Alternatives Considered

| Alternative | Reason for Rejection |
|-------------|----------------------|
| **GitHub Actions only** | Vendor lock-in — can't deploy if GitHub is down |
| **Woodpecker only** | Overhead of running CI server before self-hosting is set up |
| **Self-hosted Gitea Actions** | Premature — no Gitea instance running yet |
| **Drone CE** | More complex than Woodpecker for the same capability |

## Validation

All CI workflows are validated by:
1. Pushing a branch and confirming workflow runs green
2. Running `make validate` locally and getting identical results
3. Running deployment script locally end-to-end

## References

- [GitHub Actions validate workflow](../../.github/workflows/validate.yml)
- [GitHub Actions deploy workflow](../../.github/workflows/deploy.yml)
- [Woodpecker CI skeleton](../../.woodpecker.yml)
- [ci/README.md](../../ci/README.md)