# Host Bootstrap Runbook

Prepare a macOS host (M3 Mac) for running the CircuitHQ homelab platform.

## Prerequisites

- macOS (Apple Silicon or Intel)
- Administrative access (sudo)
- Internet connection
- At least 20GB free disk space
- At least 8GB RAM

## Step 1: Install Docker Runtime

Choose one of the following:

### Option A: OrbStack (Recommended)

```bash
brew install orbstack
```

Start OrbStack and verify:
```bash
docker version
docker compose version
```

### Option B: Docker Desktop

```bash
brew install --cask docker
```

Open Docker Desktop, accept the license, and verify:
```bash
docker version
docker compose version
```

### Option C: Colima

```bash
brew install colima docker docker-compose
colima start --arch arm64 --memory 8 --cpu 4
docker version
docker compose version
```

## Step 2: Configure Docker Log Rotation

The platform includes a recommended Docker daemon config at `infra/host/docker/daemon.json`.

### For OrbStack

OrbStack manages its own daemon config — apply via the OrbStack UI or CLI:
```bash
orb config set docker-daemon-log-driver json-file
orb config set docker-daemon-log-opts '{"max-size": "10m", "max-file": "3"}'
orb restart
```

### For Docker Desktop

Docker Desktop loads `daemon.json` automatically if placed at:
```bash
cp infra/host/docker/daemon.json ~/.docker/daemon.json
```

Then restart Docker Desktop.

### For Colima

Colima passes daemon flags on startup:
```bash
colima stop
colima start --edit
# Add under docker section:
#   log-driver: json-file
#   log-opts:
#     max-size: 10m
#     max-file: "3"
```

## Step 3: Enable Firewall

```bash
# Enable macOS application firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Enable stealth mode
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Verify
scripts/bootstrap/04-setup-firewall.sh
```

## Step 4: Create Docker Networks

```bash
scripts/bootstrap/02-create-networks.sh
```

Expected: 9 Docker networks created (circuithq-proxy through circuithq-security).

## Step 5: Verify Host Readiness

```bash
scripts/bootstrap/00-check-host.sh
```

Expected output: All checks pass (Docker, Compose, disk, memory).

## Step 6: Run Validation

```bash
make validate
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Docker not found | Docker runtime not installed | Run `scripts/bootstrap/01-install-docker.sh` for guidance |
| `docker compose` not found | Compose plugin missing | OrbStack/Docker Desktop include it; Colima needs `brew install docker-compose` |
| Disk full | Logs or backups accumulating | Check Docker disk usage: `docker system df` |
| Network creation fails | Network already exists | Script is idempotent — re-run safely |
| Port conflict on 80/443 | Another service listening | Check with `lsof -i :80 -i :443` and stop conflicting service |