# Deployment Runbook

## Overview

CircuitHQ deployments are **manual by design** — no automatic deployment to production. Every deploy must be explicitly triggered and confirmed.

## Prerequisites

- Git repository cloned at `/opt/circuithq` (or your working directory)
- Docker and Docker Compose installed
- SOPS + age key configured (Phase 6)
- Secrets rendered (`./scripts/deploy/render-secrets.sh`)
- CI workflows configured (Phase 12)

## Deployment Scripts

| Script | Purpose |
|--------|---------|
| `scripts/deploy/preflight.sh` | Check host readiness: Docker, networks, volumes, disk, secrets |
| `scripts/deploy/deploy.sh` | Full deploy: snapshot, backup, secrets, preflight, up, healthcheck |
| `scripts/deploy/render-secrets.sh` | Decrypt SOPS → rendered `.env` files (Phase 6) |
| `scripts/deploy/healthcheck.sh` | Verify all 13 containers are running and responding |
| `scripts/deploy/verify-traffic.sh` | End-to-end traffic test (Traefik ping, Prometheus targets, Grafana, Authelia, Loki, Alertmanager) |
| `scripts/backup/backup.sh` | Pre-deploy backup (Phase 10) |

## Deploy Workflow

### A) Full Deploy (Recommended)

```bash
cd /opt/circuithq

# 1. Render secrets (if not already done)
./scripts/deploy/render-secrets.sh

# 2. Run the deploy script
./scripts/deploy/deploy.sh all

# You will be prompted: Type 'DEPLOY' to confirm
```

The deploy script automatically:
1. Captures pre-deploy state to `releases/<timestamp>/`
2. Runs restic backup (if configured)
3. Renders SOPS secrets
4. Runs preflight checks
5. Pulls and deploys all stacks
6. Runs health checks
7. Captures post-deploy state

### B) Single Stack Deploy

```bash
./scripts/deploy/deploy.sh proxy
./scripts/deploy/deploy.sh auth
./scripts/deploy/deploy.sh proxy auth
./scripts/deploy/deploy.sh all --skip-backup
```

### C) Dry Run (Show What Would Happen)

```bash
./scripts/deploy/deploy.sh all --dry-run
```

### D) Manual Step-by-Step Deploy

```bash
# 1. Preflight
./scripts/deploy/preflight.sh

# 2. Backup (if restic configured)
RESTIC_ENV=.secrets-rendered/production/restic.env ./scripts/backup/backup.sh

# 3. Render secrets
./scripts/deploy/render-secrets.sh

# 4. Pull latest images
for stack in proxy auth monitoring logging; do
  docker compose -f "stacks/$stack/compose.yml" pull
done

# 5. Deploy each stack
for stack in proxy auth monitoring logging; do
  docker compose -f "stacks/$stack/compose.yml" up -d
done

# 6. Health check
./scripts/deploy/healthcheck.sh

# 7. Verify traffic
./scripts/deploy/verify-traffic.sh
```

## CI Deploy (GitHub Actions)

1. Go to GitHub repo → Actions → **deploy** workflow
2. Click **Run workflow**
3. Fill in:
   - Environment: `production` or `staging`
   - Stacks: `proxy,auth,monitoring,logging` or `all`
   - Skip backup: unchecked
   - Confirmation: type `DEPLOY`
4. Click **Run workflow**

The deploy workflow runs only on the self-hosted runner.

## Rollback

### Rollback a Single Stack

```bash
# 1. Restore pre-deploy compose config from release metadata
#    (or git checkout the previous compose config)
git checkout HEAD~1 -- stacks/proxy/

# 2. Re-deploy
docker compose -f stacks/proxy/compose.yml up -d
```

### Full Rollback from Backup

```bash
# 1. Restore repo files from backup
RESTIC_ENV=.secrets-rendered/production/restic.env \
  ./scripts/backup/restore.sh latest --repo --target /tmp/rollback

# 2. Copy files back
cp -a /tmp/rollback/* /opt/circuithq/

# 3. Restore Docker volumes if needed
#    (see docs/runbooks/restore.md for volume restore steps)

# 4. Re-deploy
./scripts/deploy/deploy.sh all
```

## Post-Deploy Verification

```bash
# All containers running
./scripts/deploy/healthcheck.sh

# End-to-end traffic
./scripts/deploy/verify-traffic.sh

# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json,sys
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    print(f\"{'🟢' if t['health']=='up' else '🔴'} {t['labels']['job']}: {t['health']}\")
"

# Validate all
make validate
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|------|
| `Type 'DEPLOY' to confirm` fails | Case mismatch | Type exactly `DEPLOY` |
| Preflight disk check fails | Disk >85% | Free space before deploying |
| `docker compose pull` fails | Rate limited / no internet | Check Docker Hub auth or pull cache |
| Container not starting | Port conflict | `docker ps` — check for port-in-use |
| Health check fails | Container not healthy | `docker logs <container> --tail=30` |
| Secrets not found | `render-secrets.sh` not run | Run `./scripts/deploy/render-secrets.sh` |
| Release metadata empty | `releases/` dir not writable | Check permissions on repo root |

## Release Metadata

Every deployment writes metadata to `releases/<timestamp>/`:

```
releases/20261201T020000Z/
├── git-sha.txt              # Commit that was deployed
├── running-images.txt        # Pre-deploy image digests
├── compose-*.yaml            # Pre-deploy rendered compose
├── container-state.txt       # Pre-deploy container statuses
├── deploy-result.txt         # "deploy-ok"
└── post/                     # Post-deploy state
```

See `releases/README.md` for full format details.