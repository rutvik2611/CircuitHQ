# Restore Runbook

## Overview

Restore procedures for recovering CircuitHQ from restic backups. Always test restore before it's needed — `restore-test.sh` runs automatically after every backup.

## List Available Snapshots

```bash
# All snapshots
restic snapshots

# Filter by tag
restic snapshots --tag repo
restic snapshots --tag volume

# Latest snapshot details (JSON for scripting)
restic snapshots --json | python3 -c "
import json,sys
snaps = json.load(sys.stdin)
snaps.sort(key=lambda x: x['time'], reverse=True)
for s in snaps[:5]:
    print(f\"{s['short_id']}  {s['time'][:19]}  tags={s.get('tags', [])}\")
"
```

## Quick Restore (Test)

```bash
# Restore latest repo config to /tmp
./scripts/backup/restore.sh latest --target /tmp/restore

# Restore specific snapshot
./scripts/backup/restore.sh abc123def --target /tmp/restore

# Restore only volumes
./scripts/backup/restore.sh latest --volumes --target /tmp/restore
```

## Full Restore Scenarios

### Scenario A: Lost repo (files deleted, not .git)

```bash
# 1. Restore repo files
./scripts/backup/restore.sh latest --repo --target /opt/circuithq

# 2. Verify
ls /opt/circuithq/Makefile
ls /opt/circuithq/stacks/

# 3. Nothing else needed — Docker volumes are safe
```

### Scenario B: Lost Docker volume

```bash
# 1. Find the latest volume snapshot
restic snapshots --tag volume

# 2. Restore the tar archive
./scripts/backup/restore.sh latest --volumes --target /tmp/vol-restore

# 3. Find the volume tar
ls /tmp/vol-restore/volumes/

# 4. Restore into a new Docker volume
docker volume create circuithq-grafana-data-temp
docker run --rm \
  -v circuithq-grafana-data-temp:/dest \
  -v /tmp/vol-restore/volumes:/src:ro \
  alpine sh -c "tar xzf /src/circuithq-grafana-data.tar -C /dest"

# 5. Stop Grafana, swap volumes, restart
docker compose -f stacks/monitoring/compose.yml down grafana
docker volume rm circuithq-grafana-data
docker volume create --name circuithq-grafana-data
docker run --rm -v circuithq-grafana-data:/dest -v circuithq-grafana-data-temp:/src:ro \
  alpine sh -c "cp -a /src/. /dest/"
docker volume rm circuithq-grafana-data-temp
docker compose -f stacks/monitoring/compose.yml up -d grafana
```

### Scenario C: Full disaster recovery (new host)

```bash
# 1. Prepare the host
#    - Install Docker, Docker Compose
#    - Clone the repo
git clone https://github.com/rutvik2611/CircuitHQ.git /opt/circuithq

# 2. Set up SOPS + age (Phase 6)
#    - Copy age key to ~/.config/sops/age/keys.txt
#    - Verify with: sops --decrypt secrets/production/restic.sops.yaml

# 3. Restore repo files from backup
cd /opt/circuithq
RESTIC_ENV=.secrets-rendered/production/restic.env \
  ./scripts/backup/restore.sh latest --repo

# 4. Restore Docker volumes
RESTIC_ENV=.secrets-rendered/production/restic.env \
  ./scripts/backup/restore.sh latest --volumes --target /tmp/vol-restore

for tarfile in /tmp/vol-restore/volumes/*.tar; do
  volname=$(basename "$tarfile" .tar)
  docker volume create "$volname"
  docker run --rm -v "${volname}:/dest" -v /tmp/vol-restore/volumes:/src:ro \
    alpine sh -c "tar xzf /src/$(basename $tarfile) -C /dest"
done

# 5. Deploy stacks
./scripts/deploy/render-secrets.sh
cd stacks/proxy && docker compose up -d
cd stacks/auth && docker compose up -d
cd stacks/monitoring && docker compose up -d
cd stacks/logging && docker compose up -d
```

### Scenario D: Database (Postgres) recovery

```bash
# 1. Restore dump from backup
./scripts/backup/restore.sh latest --database --target /tmp/db-restore

# 2. Start a temporary Postgres container
docker run -d --name circuithq-pg-restore \
  -e POSTGRES_PASSWORD=temp \
  postgres:16

# 3. Restore the dump
sleep 5  # Wait for PG to start
docker exec -i circuithq-pg-restore psql -U postgres < /tmp/db-restore/database/postgres.sql

# 4. Verify
docker exec circuithq-pg-restore psql -U postgres -c "\l"

# 5. Clean up
docker stop circuithq-pg-restore && docker rm circuithq-pg-restore
rm -rf /tmp/db-restore
```

## Verify Restore

```bash
# Run automated restore test (tests most recent snapshot)
./scripts/backup/restore-test.sh

# Manual verification
restic stats --latest
restic diff <snapshot1> <snapshot2>  # Compare two snapshots
```

## Key Files to Verify After Restore

| File | Why |
|------|-----|
| `Makefile` | All validation targets |
| `.sops.yaml` | Secret encryption config |
| `compose/networks.yml` | Docker network definitions |
| `stacks/proxy/compose.yml` | Traefik (ingress gateway) |
| `stacks/auth/compose.yml` | Authelia authentication |
| `stacks/monitoring/compose.yml` | Metrics collection |
| `secrets/` | SOPS-encrypted credentials |

## Safety Notes

- **Always test restore in a staging directory** before overwriting live data
- **Do not restore volumes** while the corresponding service is running (data races)
- **Do not restore acme.json** directly — Let's Encrypt will re-issue certificates
- **Keep the previous snapshot** until you've verified the restore
- **Document the restore RPO/RTO** after the first full restore test