# Security Infrastructure — Principle of Least Privilege

## Overview

CircuitHQ follows a **defense-in-depth** security model. This document covers host-level and infrastructure security controls, complementing the application-layer security provided by Authelia (Phase 7) and Traefik (Phase 4).

## Security Posture

```
┌────────────────────────────────────────────────┐
│                 Internet                         │
├──────────────────────┬─────────────────────────┤
│  Cloudflare WAF      │  Cloudflare Tunnel       │
│  (DDoS, bot, OWASP)  │  (no open inbound ports)  │
├──────────┬───────────┴─────────────────────────┤
│  Traefik │  TLS 1.2/1.3, HSTS, security hdrs    │
│          │  Rate limiting, IP whitelisting        │
├──────────┼──────────────────────────────────────┤
│ Authelia │  MFA (TOTP/WebAuthn), SSO, RBAC      │
├──────────┼──────────────────────────────────────┤
│   Host   │  Firewall, Docker daemon hardening,    │
│          │  SSH via Tailscale only, automatic     │
│          │  updates                               │
└──────────┴──────────────────────────────────────┘
```

## Host Hardening

### SSH

- SSH is **disabled entirely** — all administration via Tailscale SSH
- If SSH must be enabled: key-only auth, no root login, port 2222

### Firewall (pf on macOS, iptables/nftables on Linux)

```bash
# macOS — configured via scripts/bootstrap/04-setup-firewall.sh
# Default: block all inbound except established connections
# No ports 80 or 443 are exposed (Cloudflare Tunnel handles ingress)
```

### Automatic Updates

```bash
# macOS: Software Update auto-check enabled
# Linux: unattended-upgrades configured for security patches
sudo softwareupdate --schedule on      # macOS
```

### Docker Daemon Security

```json
{
  "icc": false,
  "live-restore": true,
  "userland-proxy": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "no-new-privileges": true
}
```

Key settings:
- `icc: false` — disable inter-container communication (default bridge)
- `live-restore: true` — keep containers running if dockerd restarts
- `userland-proxy: false` — avoid double NAT; use hairpin NAT
- `log-driver` with rotation to prevent disk fills

## Container Hardening

### Universal Rules

Applied to every service unless documented exception exists:

| Rule | Implementation | Exception |
|------|---------------|-----------|
| Read-only root filesystem | `read_only: true` where possible | Services needing /tmp writes |
| Drop all capabilities | `cap_drop: [ALL]` + add only needed | cAdvisor needs privileged |
| No new privileges | `security_opt: [no-new-privileges:true]` | — |
| Non-root user | `user: 1000:1000` | Services needing root |
| Restart policy | `restart: unless-stopped` | One-shot jobs use `no` |
| Log rotation | `max-size: 10m`, `max-file: 3` | — |

### Documented Exceptions

| Service | Exception | Rationale |
|---------|-----------|-----------|
| cAdvisor | `privileged: true` | Needs access to /sys, /proc, /var/run for container metrics |
| Node Exporter | `network_mode: host` | Required for real host network metrics |
| Promtail | Docker socket mount | Reads container metadata labels from Docker API |
| Traefik | Docker socket mount | Docker provider service discovery |

## CrowdSec (Optional)

CrowdSec provides IP-level threat intelligence and blocking based on behavior patterns.

```bash
# Deploy CrowdSec as a Docker container
docker run -d --name circuithq-crowdsec \
  -v crowdsec-data:/var/lib/crowdsec/data \
  -v crowdsec-config:/etc/crowdsec \
  --network circuithq-security \
  crowdsecurity/crowdsec

# Integration with Traefik via bouncer
# See: https://docs.crowdsec.net/u/bouncers/traefik/
```

**Not yet deployed** — planned for Phase 11+.

## Fail2ban (Linux Only)

For native firewall-based IP blocking:

```bash
# Install
sudo apt install fail2ban

# Configure SSH jail (if SSH is enabled)
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo sed -i 's/^\[sshd\]/[sshd]\nenabled = true/' /etc/fail2ban/jail.local
sudo systemctl enable --now fail2ban

# Traefik bouncer (requires CrowdSec instead for HTTP-level blocking)
```

## Secret Management

- All secrets encrypted with **SOPS + age**
- Age private key at `~/.config/sops/age/keys.txt` (0600 perms)
- Runtime secrets rendered to `.secrets-rendered/` (0600, .gitignore'd)
- No `.env` files committed to Git
- See Phase 6 and `secrets/README.md` for full details

## Network Security

| Network | Type | Purpose |
|---------|------|---------|
| `circuithq-public` | Internal (`internal: false`) | Public-facing app traffic |
| `circuithq-private` | Internal | Backend service communication |
| `circuithq-management` | Internal | Management/administration |
| `circuithq-monitoring` | Internal | Metrics and logs |
| `circuithq-database` | Internal | Database access |
| `circuithq-security` | Internal | Auth services |
| `circuithq-backup` | Internal | Backup traffic |
| `circuithq-proxy` | Internal | Traefik → upstream routing |
| `circuithq-shared` | Internal | Shared service discovery |

Internal networks (`internal: true`) have no external route, preventing container escape lateral movement.

## Update Policy

| Component | Update Frequency | Method |
|-----------|-----------------|--------|
| Docker images | Weekly or on CVE | `docker compose pull && docker compose up -d` |
| Docker daemon | Automatic (macOS) | Software Update |
| Linux kernel | Automatic | unattended-upgrades |
| SOPS/age | As needed | `brew upgrade sops age` |
| Restic | As needed | `brew upgrade restic` |

## Incident Response

See `docs/runbooks/security.md` (planned for Phase 15).

## Validation

```bash
# Run all security validations
make security-scan

# Specific checks
bash scripts/validate/validate-permissions.sh
bash scripts/validate/validate-compose-security.sh
bash ci/scripts/ci-scan.sh
```