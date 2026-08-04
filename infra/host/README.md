# CircuitHQ — Deployment Target: M3 Mac Laptop

## Overview

The CircuitHQ platform is designed to run on this M3 Mac laptop. The laptop serves as both the **development workstation** and the **production deployment target** — every compose file, script, and workflow is validated here before being considered ready.

```
┌──────────────────────────────────────┐
│         M3 Mac Laptop                 │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  Self-Hosted GitHub Actions     │  │
│  │  Runner (validate + deploy)     │  │
│  └─────────────────────────────────┘  │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  Docker / OrbStack              │  │
│  │                                 │  │
│  │  Traefik → Authelia → Apps     │  │
│  │  Prometheus → Grafana → Loki   │  │
│  └─────────────────────────────────┘  │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │  Tailscale (private admin)      │  │
│  │  Cloudflare Tunnel (public)     │  │
│  │  SOPS + age (secrets)           │  │
│  └─────────────────────────────────┘  │
└──────────────────────────────────────┘
```

## Host Specification

| Property | Value |
|----------|-------|
| **Model** | Apple M3 Mac |
| **OS** | macOS 15.x (Sequoia) |
| **Architecture** | ARM64 (Apple Silicon) |
| **Docker Runtime** | OrbStack |
| **Docker Compose** | ✅ Installed |
| **Project Path** | `/Users/rutvik2611/Projects/CircuitHQ` |
| **Age Key Path** | `~/.config/sops/age/keys.txt` (0600) |
| **SOPS** | ✅ Installed |
| **Tailscale** | ✅ Installed |
| **Tailscale Hostname** | `circuithq-laptop` |
| **GitHub CLI (gh)** | ✅ Installed |

## Deploy Target Modes

### Local (Default)

The deploy pipeline targets `localhost`:

```bash
# Full deploy (interactive confirmation)
./scripts/deploy/deploy.sh all

# Dry run
./scripts/deploy/deploy.sh all --dry-run

# Single stack
./scripts/deploy/deploy.sh proxy
```

### CI Deploy (GitHub Actions)

Requires typed confirmation in the GitHub Actions UI:

1. Go to GitHub repo → Actions → **deploy-laptop** workflow
2. Click **Run workflow**
3. Set parameters and type `I_APPROVE_LAPTOP_DEPLOY`
4. Click **Run workflow**

The deploy-laptop workflow is guarded by:
- `docs/approvals/laptop-cicd-retarget-approved.md` approval gate
- `laptop-production` GitHub Environment with required reviewers
- Typed confirmation field

## Pre-deploy Checklist

Before deploying to the laptop:

- [x] `make validate` passes
- [ ] Age key exists at `~/.config/sops/age/keys.txt`
- [ ] Secrets rendered: `./scripts/deploy/render-secrets.sh`
- [ ] All required Docker networks exist
- [ ] All required Docker volumes exist
- [ ] Disk usage < 85%
- [ ] Tailscale connected (for private admin access)
- [ ] Cloudflare Tunnel token valid (for public ingress)
- [ ] Docker daemon running

## Post-deploy Verification

```bash
# Health check
./scripts/deploy/healthcheck.sh

# Traffic verification
./scripts/deploy/verify-traffic.sh

# Full validation
make validate

# Check release metadata
ls releases/ | tail -1
cat releases/$(ls releases/ | tail -1)/deploy-result.txt
```

## Self-Hosted Runner

This M3 Mac runs a self-hosted GitHub Actions runner for CI validation and deployment.

### Runner Identity

| Property | Value |
|----------|-------|
| **Runner Name** | m3-mac-runner |
| **Labels** | `self-hosted`, `macos`, `m3`, `homelab-validation` |
| **Work Dir** | `~/actions-runner/_work` |
| **Service** | Installed via `svc.sh` |

### Repository Variables

Set these in GitHub repo → Settings → Secrets and variables → Actions:

| Variable | Value |
|----------|-------|
| `SELF_HOSTED_RUNNER` | `self-hosted` |
| `DEPLOY_HOST` | `localhost` |
| `PROJECT_DIR` | `/Users/rutvik2611/Projects/CircuitHQ` |
| `DEPLOY_USER` | `runner` |

See `ci/README.md` for the full runner setup guide.

## Deployment Target Workflows

| Workflow | Trigger | Target | Guard |
|----------|---------|--------|-------|
| `validate.yml` | Push/PR | Laptop (local) | None |
| `deploy.yml` | Manual | Configurable (default: localhost) | `DEPLOY` typed confirmation |
| `deploy-laptop.yml` | Manual | Laptop (production) | `I_APPROVE_LAPTOP_DEPLOY` + `docs/approvals/laptop-cicd-retarget-approved.md` + `laptop-production` environment |

## Security

| Control | Status |
|---------|--------|
| Age private key | 0600, never committed |
| SOPS-encrypted secrets | All secrets committed as encrypted `.sops.yaml` |
| Rendered secrets | 0600, `.gitignore`'d |
| Self-hosted runner | Least-privilege user (Docker + git only) |
| Deploy approval gate | Typed confirmation + environment protection |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Cannot connect to the Docker daemon` | OrbStack not running | Start OrbStack |
| `sops: command not found` | SOPS not installed | `brew install sops` |
| Age key not found | Missing `keys.txt` | `age-keygen -o ~/.config/sops/age/keys.txt` |
| `docker compose pull` fails | Network / rate limit | Check Docker Hub auth or internet |
| Deploy workflow fails at gate step | Approval doc missing | Create `docs/approvals/laptop-cicd-retarget-approved.md` |
| Runner not found in CI | Runner service not running | Check `~/actions-runner/svc.sh status` |