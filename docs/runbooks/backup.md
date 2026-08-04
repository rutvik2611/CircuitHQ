# Backup Runbook

## Prerequisites

- restic installed (`brew install restic` or `apt install restic`)
- SOPS + age key configured (Phase 6)
- Restic repository initialized (see Setup section)

## Setup

### Step 1: Initialize Restic Repository

Choose a storage backend and initialize the repository:

```bash
# Local (external disk)
restic init --repo /mnt/backup/circuithq

# S3
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
restic init --repo s3:s3.amazonaws.com/circuithq-backups

# SFTP
restic init --repo sftp:user@backup-server:/backups/circuithq
```

Enter the repository password when prompted — this is the master encryption key.

### Step 2: Configure SOPS Secret

```bash
# Create restic secrets file
sops secrets/production/restic.sops.yaml

# Add:
#   RESTIC_REPOSITORY=s3:s3.amazonaws.com/circuithq-backups
#   RESTIC_PASSWORD=<your-repo-password>
#   AWS_ACCESS_KEY_ID=...
#   AWS_SECRET_ACCESS_KEY=...
```

### Step 3: Render Runtime Env

```bash
ENV=production ./scripts/deploy/render-secrets.sh
# Output → .secrets-rendered/production/restic.env
```

### Step 4: Set Up Systemd Timer

```bash
# Copy service/timer files
sudo cp scripts/backup/backup.service /etc/systemd/system/circuithq-backup.service
sudo cp scripts/backup/backup.timer /etc/systemd/system/circuithq-backup.timer

# Edit service to point to the correct script path
sudo sed -i 's|/opt/circuithq|/home/user/circuithq|g' /etc/systemd/system/circuithq-backup.service

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable --now circuithq-backup.timer

# Verify
sudo systemctl list-timers circuithq-backup.timer
```

## Manual Backup

```bash
# Run full backup
./scripts/backup/backup.sh

# Dry run (show what would be backed up)
DRY_RUN=true ./scripts/backup/backup.sh

# Verbose output
VERBOSE=true ./scripts/backup/backup.sh
```

## Check Repository Integrity

```bash
# Quick check (structure only)
./scripts/backup/check.sh

# Full check (reads all data — slow for large repos)
restic check --read-data
```

## List Snapshots

```bash
# Via restic directly
restic snapshots

# Grouped by tag
restic snapshots --tag repo
restic snapshots --tag volume

# Latest snapshot details
restic stats --latest
```

## Monitor Backup Health

**Uptime Kuma:**
1. Create a **Push Monitor** in Uptime Kuma
2. Copy the push URL
3. Add it to `secrets/production/restic.sops.yaml` as `UPTIME_KUMA_PUSH_URL`

**Prometheus (via restic_exporter):**
```bash
# Optional: run restic_exporter for Prometheus metrics
docker run -d --name restic-exporter \
  -v /etc/circuithq/secrets/restic.env:/etc/restic/env:ro \
  -p 9752:9752 \
  silex/restic-exporter
```

## Logs

```bash
# View backup logs (if syslog configured)
journalctl -u circuithq-backup.service --since "1 day ago"

# Or check the backup script's log file
tail -50 /var/log/circuithq/backup-*.log
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|------|
| `Fatal: unable to open config file` | Repository not initialized | Run `restic init` first |
| `wrong password` | RESTIC_PASSWORD mismatch | Check SOPS decryption and env file |
| `connection refused` | S3/SFTP endpoint unreachable | Check network and credentials |
| `s3: AccessDenied` | AWS credentials wrong | Rotate or update access keys |
| `snapshot not found` | Wrong snapshot ID | `restic snapshots` to list |
| `Permission denied` | Files not accessible to restic | Run as root or adjust permissions |
| `no space left on device` | Backup destination full | Add capacity or tighten retention |
| Backup test failing | repo files changed location | Update restore-test.sh checks |