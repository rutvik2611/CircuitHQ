# Backup Architecture — restic

## Overview

CircuitHQ uses **restic** for encrypted, snapshot-based backups of all critical data. Backups run daily via systemd timer and are stored in a remote restic repository.

```
                        ┌──────────────────────┐
                        │    Restic Repository   │
                        │  (S3 / SFTP / Local)   │
                        └──────────┬───────────┘
                                   │ encrypted
                                   │ snapshot-based
                                   │ de-duplicated
                                   ▼
┌─────────────────────────────────────────────────┐
│              backup.sh (daily)                   │
├─────────────────────────────────────────────────┤
│  • Repo config (git-tracked files)               │
│  • Docker volumes (tar streaming via containers) │
│  • Postgres dump (pg_dumpall)                    │
│  • ACME certificates (traefik-acme volume)       │
│  • System logs (last 24h via journalctl)         │
└─────────────────────────────────────────────────┘
```

## Components

| Component | Purpose | Script |
|-----------|---------|--------|
| **backup.sh** | Main backup — collects all sources, streams to restic | `scripts/backup/backup.sh` |
| **restore.sh** | Restore from snapshot with filter options | `scripts/backup/restore.sh` |
| **check.sh** | Repository integrity verification | `scripts/backup/check.sh` |
| **forget-prune.sh** | Retention policy enforcement + data pruning | `scripts/backup/forget-prune.sh` |
| **restore-test.sh** | Automated restore test (verifies key files present) | `scripts/backup/restore-test.sh` |
| **backup.service** | systemd service unit | `scripts/backup/backup.service` |
| **backup.timer** | systemd timer (daily at 02:00) | `scripts/backup/backup.timer` |

## Backup Sources

| Source | Method | Tag | Priority |
|--------|--------|-----|----------|
| Repository files | `restic backup` with exclude patterns | `repo` | Critical |
| Docker volumes | Tar stream via ephemeral container | `volume` | Critical |
| Postgres database | `pg_dumpall` piped to restic stdin | `database` | High |
| ACME certificates | Direct path from traefik-acme volume | `acme` | High |
| System logs | `journalctl --since 24h` piped to stdin | `logs` | Low |

### Docker Volumes Backed Up

- `circuithq-prometheus-data` — Prometheus TSDB (30 days metrics)
- `circuithq-grafana-data` — Grafana dashboards, config
- `circuithq-loki-data` — Loki log chunks, indexes
- `circuithq-traefik-acme` — Let's Encrypt certificates
- `circuithq-redis-data` — Authelia session store
- `circuithq-uptime-kuma-data` — Uptime Kuma configuration
- `circuithq-authelia-config` — Authelia user database

## Encryption

- **Algorithm:** AES-256-GCM (restic default)
- **Key:** Repository password stored in SOPS-encrypted `secrets/production/restic.sops.yaml`
- **Transport:** Configurable (S3 with TLS, SFTP, local filesystem)
- At-rest encryption in restic repository + in-transit encryption via transport layer

## Retention Policy

| Interval | Keep | Effective Window |
|----------|------|-----------------|
| Hourly | 24 | 24 hours |
| Daily | 7 | 7 days |
| Weekly | 4 | 28 days |
| Monthly | 3 | 90 days |
| Yearly | 1 | 365 days |

Policy is enforced by `forget-prune.sh` (run automatically after each backup).

## Restore Test

After every successful backup, `restore-test.sh`:
1. Restores the latest snapshot to `/tmp/circuithq-restore-test`
2. Verifies key files exist (Makefile, compose files, stack configs)
3. Cleans up the test directory
4. Fails (exit 1) if any expected file is missing

This ensures backups are actually restorable, not just present.

## Notification

On completion, backup.sh sends a push notification to Uptime Kuma (if `UPTIME_KUMA_PUSH_URL` is configured) so the status page reflects backup health.

## Scheduling

systemd timer runs `backup.service` daily at 02:00 with a 1-hour randomized delay to spread load.

## Security

- **Restricted systemd unit:** `ProtectSystem=full`, `PrivateTmp=true`, `NoNewPrivileges=true`
- **Credentials:** Loaded from SOPS-decrypted file at `/etc/circuithq/secrets/restic.env` (0600)
- **No hardcoded secrets:** Repository URL and password only known at runtime via SOPS
- **Restore test is ephemeral:** Temp directory cleaned up after verification

## Directory Structure

```
scripts/backup/
├── backup.sh                    # Main backup script
├── restore.sh                   # Snapshot restore
├── check.sh                     # Repository integrity check
├── forget-prune.sh              # Retention enforcement
├── restore-test.sh              # Automated restore test
├── backup.service               # systemd service unit
└── backup.timer                 # systemd timer (daily)

secrets/production/
└── restic.sops.yaml             # Repository credentials (SOPS encrypted)
```