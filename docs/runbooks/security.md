# Security Incident Response Runbook

## Overview

This runbook covers procedures for detecting, containing, and recovering from security incidents in the CircuitHQ homelab platform. The layered defense model means a single breach is unlikely to compromise the entire system, but rapid response limits blast radius.

**All times in UTC.** Every incident should be logged to the incident log (see below).

## Incident Severity Levels

| Level | Label | Example | Response Time |
|-------|-------|---------|---------------|
| P1 | Critical | Active container escape, known RCE, secrets leak | Immediate |
| P2 | High | Unexplained network traffic, unauthorized access | 1 hour |
| P3 | Medium | Suspicious logs, failed auth attempts spike | 24 hours |
| P4 | Low | Port scan, non-critical CVEs | Next maintenance |

## Incident Log

Record every incident — even false alarms — to `/var/log/circuithq/incidents/YYYY-MM-DD-<title>.md`:

```markdown
# Incident: <title>
**Date:** YYYY-MM-DD HH:MM UTC
**Severity:** P1/P2/P3/P4
**Detected by:** <monitor alert / manual / external report>
**Status:** open / investigating / contained / resolved

## Timeline
- HH:MM — First observation
- HH:MM — Containment action taken
- HH:MM — Root cause identified
- HH:MM — Resolution verified

## Evidence
- Container logs: <path>
- Network logs: <path>
- Metrics snapshots: <path>

## Root Cause

## Actions Taken

## Lessons Learned
```

## Detection

### Automated Monitoring

| Source | What it detects | Alert channel |
|--------|----------------|---------------|
| Prometheus + Alertmanager | Container down, high error rate, disk full, cert expiry | Slack + Email |
| Traefik access logs | 5xx spike > 5%, 4xx spike > 20% | Grafana Loki alert |
| Cloudflare WAF | OWASP rule matches, rate limit hits, bot activity | Cloudflare dashboard |
| Docker events | Container start/stop/kill (unexpected) | Journald / Loki |

### Manual Indicators to Investigate

- **Unknown containers running:** `docker ps` shows services not in compose files
- **Network connections to unknown IPs:** `lsof -i` or `netstat -an`
- **Unexpected volume mounts or ports:** Check compose files against running containers
- **Modified files in tracked directories:** `git status` shows unexpected changes
- **Failed authentication spikes:** Authelia logs show repeated failures from single IP
- **Alertmanager silence that wasn't set by you** — check who silenced what

## P1: Active Container Escape / RCE

### Containment

```bash
# 1. IMMEDIATELY isolate the affected container(s)
docker network disconnect circuithq-proxy <affected-container>
docker network disconnect circuithq-monitoring <affected-container>

# 2. Stop the affected stack(s)
docker compose -f stacks/<affected-stack>/compose.yml down --timeout 10

# 3. Snapshot container logs before they're lost
docker logs <affected-container> > /tmp/incident-log-$(date +%s).txt 2>&1

# 4. If the host itself is compromised:
#    - Disconnect from Tailscale
sudo tailscale down
#    - Disconnect from Cloudflare Tunnel
docker compose -f stacks/proxy/cloudflared/compose.yml down
#    - Block all Docker traffic
sudo pfctl -F all
```

### Investigation

```bash
# Export all logs for analysis
docker compose logs --timestamps > /tmp/incident-logs-$(date +%s).txt

# Check for unknown processes
docker ps -a

# Check for modified compose/config files
cd /opt/circuithq
git status
git diff

# Check Docker daemon logs
sudo journalctl -u docker --since "24 hours ago" | grep -i error
```

### Recovery

```bash
# 1. Revoke all credentials that touched the compromised host
#    - Cloudflare tunnel token: revoke from Zero Trust dashboard
#    - Tailscale key: revoke from admin console
#    - GitHub deploy token: revoke from repo settings
#    - Restic password: change and re-encrypt snapshots

# 2. Restore from clean backup
git stash --all
git checkout <last-known-good-commit>
./scripts/deploy/render-secrets.sh
./scripts/deploy/deploy.sh all

# 3. Rotate all secrets in SOPS
sops secrets/production/*.sops.yaml

# 4. Verify restore
make validate
./scripts/deploy/healthcheck.sh
```

## P2: Unauthorized Access

### Immediate Actions

```bash
# 1. Identify the source IP/device
# Check Traefik access logs
docker compose -f stacks/proxy/compose.yml logs traefik --tail=100 | grep -E "401|403|unauthorized"

# Check Authelia logs
docker compose -f stacks/auth/compose.yml logs authelia --tail=50 | grep -E "failed|denied|unauthorized"

# Check Tailscale connections
tailscale status
tailscale serve status

# 2. Revoke access
#    - Remove user from Authelia users_database.yml
#    - Remove device from Tailscale admin console
#    - Add IP to Traefik IP blacklist middleware

# 3. Reset all sessions
docker compose -f stacks/auth/compose.yml restart authelia
```

### Investigation

```bash
# Check for credential stuffing
docker compose logs authelia | grep -c "authentication failed"

# Check for access after hours
docker compose logs authelia | grep "$(date -d 'yesterday' +%Y-%m-%dT%H:00:00)"

# Review Tailscale ACL audit log (admin console)
# Review Cloudflare audit log (dashboard → Account → Audit Log)
```

## P3: Suspicious Activity

### Investigation Checklist

- [ ] Review Traefik access logs for unusual patterns (non-200 status, long paths, unusual User-Agents)
- [ ] Review Authelia logs for brute-force attempts
- [ ] Review Prometheus alert history for silenced alerts
- [ ] Review Docker events: `docker events --since 24h`
- [ ] Review system logs: `journalctl --since "24 hours ago" --priority=err`
- [ ] Check for unexpected cron jobs: `crontab -l` and `ls /etc/cron*`
- [ ] Verify file integrity: `git status` and `git log --oneline -10`

### Escalation Criteria

Escalate to P2 if any of:
- Multiple failed auth attempts from the same IP (10+ in 5 minutes)
- Known CVE with active exploits for any running image
- File modification without corresponding git diff
- Network connection to a known malicious IP (check via VirusTotal)

## P4: Low Severity Events

### Handling

```bash
# Log and track — no immediate action unless patterns emerge
# Add to incident log and review during next maintenance window
```

Common P4 events:
- Port scans (Cloudflare WAF catches these)
- Failed SSH attempts (should be none if SSH is disabled)
- Rate limit hits from legitimate crawlers
- Certificate expiry warnings

## Prevention & Hardening

### Regular Tasks

| Frequency | Task | Script |
|-----------|------|--------|
| Weekly | Pull latest container images | `for d in stacks/*/; do docker compose -f "$d/compose.yml" pull; done` |
| Weekly | Run Trivy vuln scan | `trivy fs --scanners vuln .` |
| Monthly | Check for Docker CVEs | `docker scan <image>` or Trivy |
| Monthly | Review Authelia access logs | `docker compose logs authelia --since "30 days"` |
| Quarterly | Rotate Cloudflare tokens | Dashboard → API Tokens |
| Quarterly | Rotate tailnet key | Tailscale admin console |
| Quarterly | Review Tailscale ACLs | `infra/tailscale/policy.hujson` |

### Automated Defenses in Place

- **Container isolation:** 9 isolated Docker networks, most internal-only
- **No privileged containers** except cAdvisor (documented exception)
- **Read-only filesystems** where possible
- **Secrets never in Git** — all SOPS-encrypted
- **Rate limiting** at Traefik layer (100 req/min global, 10/min auth)
- **No SSH** — Tailscale SSH only (ACL-restricted)
- **MFA required** for all admin dashboards

## Known Gaps

| Gap | Planned Phase |
|-----|---------------|
| CrowdSec IP blocking | Future enhancement |
| Secrets rotation automation | Future enhancement |
| Docker event audit logging | Future enhancement |
| Automated incident alerting via PagerDuty/Opsgenie | Future enhancement |

## Related Documents

- [Security Architecture](../architecture/security.md)
- [infra/security/README.md](../../infra/security/README.md)
- [Authentication Runbook](authentication.md)
- [Deployment Runbook](deploy.md)
- [Traefik Runbook](traefik.md)