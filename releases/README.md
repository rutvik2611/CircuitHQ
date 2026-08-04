# Release Metadata

## Overview

Each deployment creates a timestamped release directory under `releases/` with full metadata about what was deployed and the pre-deployment state.

## Directory Structure

```
releases/
├── 20261201T020000Z/              # Timestamp of deployment (UTC ISO8601)
│   ├── git-sha.txt                # Git commit SHA (short)
│   ├── git-branch.txt             # Git branch name
│   ├── timestamp.txt              # ISO8601 deployment timestamp
│   ├── running-images.txt         # Docker image digests (pre-deploy)
│   ├── container-state.txt        # Container names + statuses (pre-deploy)
│   ├── compose-proxy.yaml         # Rendered compose config (pre-deploy)
│   ├── compose-auth.yaml          # Rendered compose config (pre-deploy)
│   ├── compose-monitoring.yaml    # Rendered compose config (pre-deploy)
│   ├── compose-logging.yaml       # Rendered compose config (pre-deploy)
│   ├── deploy-result.txt          # "deploy-ok" or error message
│   └── post/                      # Post-deploy state snapshot
│       ├── git-sha.txt
│       ├── running-images.txt
│       ├── container-state.txt
│       └── compose-*.yaml
├── 20261202T140000Z/
│   └── ...
└── README.md                      # This file
```

## Metadata File Formats

### git-sha.txt

```
a1b2c3d4
```

### running-images.txt

```
traefik:v3.3
authelia/authelia:4.38
prom/prometheus:v3.2
grafana/grafana:11.6-oss
louislam/uptime-kuma:1.23
```

### container-state.txt

```
NAMES                           STATUS                  IMAGE
circuithq-traefik               Up 14 days              traefik:v3.3
circuithq-authelia              Up 14 days              authelia/authelia:4.38
circuithq-prometheus            Up 14 days              prom/prometheus:v3.2
```

### compose-*.yaml

Full rendered Docker Compose config as produced by `docker compose config`. This includes resolved environment variables, network names, and volume paths.

### deploy-result.txt

```
deploy-ok
```

Or on failure:

```
deploy-failed: preflight disk check failed — 92% usage
```

## Usage

### View latest release

```bash
ls -1t releases/ | head -3
cat releases/$(ls -1t releases/ | head -1)/git-sha.txt
```

### Compare pre/post deployment state

```bash
diff releases/20261201T020000Z/running-images.txt releases/20261201T020000Z/post/running-images.txt
```

### Roll back to a previous release

```bash
# Check what was running at that release
cat releases/20261130T020000Z/running-images.txt

# Restore the compose config from that release (as reference)
less releases/20261130T020000Z/compose-proxy.yaml

# For full rollback, use restore.sh (see docs/runbooks/restore.md)
```

## CI Integration

When deployed via the GitHub Actions deploy workflow (`.github/workflows/deploy.yml`), the release metadata is captured inside the runner's working directory and should be committed back to the repo or persisted to a shared volume.

## Retention

Release metadata is **not automatically pruned** — it's lightweight (text files, kilobytes each). Consider pruning releases older than 90 days if disk is a concern:

```bash
find releases/ -maxdepth 1 -type d -mtime +90 -exec rm -rf {} +
```