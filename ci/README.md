# CI/CD Comparison & Runner Setup

## Overview

CircuitHQ can be validated and deployed using several free/FOSS CI systems. This document compares options and documents the self-hosted runner setup.

## CI Options Comparison

| Feature | GitHub Actions | Woodpecker CI | Gitea/Forgejo Actions | Drone CE |
|---------|---------------|---------------|----------------------|----------|
| **Hosting** | GitHub-hosted or self-hosted | Self-hosted only | Self-hosted only | Self-hosted only |
| **Free tier** | 2,000 min/mo (public: unlimited) | Unlimited (your infra) | Unlimited (your infra) | Unlimited (your infra) |
| **Runner arch** | x86_64, ARM64, macOS (M1) | Any Docker host | Any Docker host | Any Docker host |
| **M3 Mac runner** | ✅ Self-hosted macOS | ✅ Docker on macOS | ✅ Docker on macOS | ✅ Docker on macOS |
| **Secrets** | ✅ Encrypted env vars | ✅ Encrypted env vars | ✅ Encrypted env vars | ✅ Encrypted env vars |
| **Manual deploy** | ✅ `workflow_dispatch` | ✅ `deployment` event | ✅ `workflow_dispatch` | ✅ Promote |
| **Approval gates** | ✅ Environments with reviewers | ✅ Manual approval per step | ✅ Required reviewers | ✅ Promote requires approval |
| **Complexity** | Low | Medium | Medium | Low-Medium |
| **Maintenance** | None (GitHub-hosted) | Run server + agent | Run Gitea/Forgejo | Run Drone server + agent |
| **Persistence** | Stateless | SQLite/Postgres backend | SQLite/Postgres backend | SQLite/Postgres backend |

## Recommendation

| Scenario | Recommended CI | Rationale |
|----------|---------------|-----------|
| **GitHub-hosted repo** (current) | GitHub Actions (validate.yml + deploy.yml) | Zero infra, unlimited public minutes |
| **Self-hosted Gitea** | Gitea Actions (same YAML as GitHub) | Drop-in compatible, fully self-hosted |
| **Lightweight self-hosted** | Woodpecker CI | Simpler than Drone, Go binary, active community |
| **Maximum simplicity** | Drone CE | Single binary, YAML pipeline, widely adopted |

## Self-Hosted M3 Mac Runner Setup (GitHub Actions)

### Prerequisites

- M3 Mac (macOS 14+)
- Docker Desktop or OrbStack installed
- Git installed
- `gh` CLI installed and authenticated

### Install Runner

```bash
# 1. Create a runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# 2. Download the latest runner
curl -o actions-runner.tar.gz -L \
  "https://github.com/actions/runner/releases/latest/download/actions-runner-osx-arm64-2.322.0.tar.gz"
tar xzf actions-runner.tar.gz

# 3. Get a runner token from:
#    GitHub repo → Settings → Actions → Runners → New self-hosted runner
#    Then copy the config command

# 4. Configure (replace with your token)
./config.sh \
  --url https://github.com/rutvik2611/CircuitHQ \
  --token YOUR_TOKEN \
  --name m3-mac-runner \
  --labels self-hosted,macos,m3 \
  --work _work

# 5. Install as a service
sudo ./svc.sh install
sudo ./svc.sh start

# 6. Verify
sudo ./svc.sh status
```

### Configure Repository Variables

Set these in GitHub repo → Settings → Secrets and variables → Actions:

| Variable | Value | Purpose |
|----------|-------|---------|
| `SELF_HOSTED_RUNNER` | `self-hosted` | Tells workflows to use self-hosted runner |
| `DEPLOY_HOST` | `localhost` | Target host for deploy workflow |
| `DEPLOY_USER` | `runner` | SSH user for deploy (if remote) |
| `PROJECT_DIR` | `/opt/circuithq` | Project path on target |

### Set Required Secrets

| Secret | Purpose |
|--------|---------|
| `RESTIC_PASSWORD` | Backup repository encryption |
| `RESTIC_REPOSITORY` | Backup target URL |
| `DOCKERHUB_USERNAME` | Docker Hub pull-through (optional) |
| `DOCKERHUB_TOKEN` | Docker Hub auth (optional) |

## Running the Validate Workflow

### On GitHub Actions

Push to main or open a PR — `.github/workflows/validate.yml` runs automatically.

### On Woodpecker

```bash
# Copy the skeleton to project root
cp .woodpecker.yml .woodpecker.yml
# Edit and uncomment the pipeline as needed
# Commit and push — Woodpecker picks it up via webhook
```

### Locally (same checks as CI)

```bash
make validate
```

## Deploy Workflow

### Trigger

1. Go to GitHub repo → Actions → **deploy** workflow
2. Click **Run workflow**
3. Fill in:
   - Environment: `production` or `staging`
   - Stacks: `proxy,auth,monitoring,logging` or `all`
   - Skip backup: unchecked (recommended)
   - Confirmation: type `DEPLOY`
4. Click **Run workflow**

### Production Approval

- The deploy workflow runs **only on the self-hosted runner**
- Requires `DEPLOY` to be typed in the `confirm` field
- For additional safety, enable **required reviewers** on the `production` environment in GitHub repo settings

## CI File Structure

```
.github/workflows/
├── validate.yml     # Push/PR validation (lint, compose, security, secrets)
└── deploy.yml       # Manual deploy (backup, pull, up, healthcheck)

.woodpecker.yml      # Woodpecker CI skeleton (commented out)

ci/
├── README.md        # This file
└── scripts/
    └── ci-scan.sh   # Trivy + Syft scan (Phase 11)
```