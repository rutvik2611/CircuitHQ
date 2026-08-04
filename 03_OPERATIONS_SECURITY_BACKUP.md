# Operations, Security, Observability, Backup, and Restore

> Split from `HOMELAB_PLATFORM_BLUEPRINT.md` on 2026-08-04. The original giant file is retained as an archive/source reference.

Operational systems: backups, monitoring, logging, security, secrets, observability, documentation, disaster recovery, risks, checklists, and one-shot restore.

## Local Table of Contents

- [13. Backup Architecture](#13-backup-architecture)
- [14. Monitoring Architecture](#14-monitoring-architecture)
- [15. Logging Architecture](#15-logging-architecture)
- [16. Security Architecture](#16-security-architecture)
- [17. Secrets Management](#17-secrets-management)
- [18. Observability Model](#18-observability-model)
- [23. Documentation Standards](#23-documentation-standards)
- [25. Disaster Recovery Plan](#25-disaster-recovery-plan)
- [28. Risks and Mitigations](#28-risks-and-mitigations)
- [30. Appendix: Operational Checklists](#30-appendix-operational-checklists)
- [33. Daily Backup and One-Shot Git Checkpoint Restore](#33-daily-backup-and-one-shot-git-checkpoint-restore)

---

# 13. Backup Architecture

## 13.1 Backup goals

- Encrypted by default.
- Automated schedule.
- Versioned retention.
- Verified regularly.
- Restore-tested.
- Covers config, volumes, secrets, databases, certs, logs where useful.
- No paid backup SaaS required.

## 13.2 Backup architecture diagram

```text
PiKVM V4 Host
   |
   +-- Compose repository
   +-- Config directories
   +-- SOPS-encrypted secrets
   +-- Docker volumes
   +-- Database dumps
   +-- Traefik ACME/certs
   +-- Selected logs
          |
          v
Backup Orchestrator
   +-- pre-backup hooks
   |      +-- pause/flush if needed
   |      +-- database dumps
   +-- restic/Borg encrypted backup
   +-- prune retention
   +-- check repository
   +-- restore test sample
   +-- notify status
          |
          v
Backup Targets
   +-- local USB SSD
   +-- NAS over SSH/SFTP
   +-- second homelab node
   +-- offline rotated disk
```

## 13.3 Recommended backup software

Primary recommendation: **restic**.

Why:

- Free and open-source.
- Strong encryption.
- Supports local, SFTP, REST server, S3-compatible, rclone backends.
- Good deduplication.
- Easy restore.

Alternative: **BorgBackup**.

Why:

- Very mature.
- Excellent deduplication.
- Great over SSH.

Optional helper: **rclone** for moving encrypted restic repositories to additional self-hosted targets.

## 13.4 What to back up

| Data | Backup method | Frequency | Notes |
|---|---|---|---|
| Git repo / Compose files | Git + restic | Every deploy + daily | Git is not enough if remote unavailable |
| Config directories | restic | Daily + pre-deploy | Include Traefik, Authelia, monitoring configs |
| SOPS encrypted secrets | Git + restic | On change + daily | Safe to store encrypted copies |
| Decrypted runtime secrets | Avoid if possible | If backed up, encrypted restic only | Prefer regenerating from SOPS |
| Docker volumes | restic | Daily | Stop/quiesce if app requires consistency |
| Databases | logical dump + restic | Daily + pre-deploy | `pg_dump`, `mysqldump`, SQLite copy with lock |
| Certificates/ACME | restic | Daily + on renew | Restrict restore permissions |
| Logs | Loki retention + optional restic | Depends | Keep only useful retention |
| CI artifacts/releases | Git release + restic | On release | Needed for rollback |

## 13.5 Backup schedule

Recommended baseline:

| Schedule | Task |
|---|---|
| Hourly | Lightweight config backup for critical configs if changes frequent |
| Daily | Full restic backup of configs, volumes, DB dumps |
| Weekly | Repository check + sample restore |
| Monthly | Full disaster recovery restore test to temporary directory/host |
| Before deploy | Pre-deploy snapshot and DB dump |
| Before upgrade | Full backup + restore validation |

## 13.6 Retention policy

Example restic retention:

- Keep hourly: 24
- Keep daily: 14
- Keep weekly: 8
- Keep monthly: 12
- Keep yearly: 3 if storage allows

Adjust for storage size.

## 13.7 Backup verification

Backups are not real until restored.

Verification tasks:

- `restic check` weekly.
- Restore random file weekly.
- Restore critical service config monthly.
- Restore database dump to temporary container monthly.
- Perform full platform restore drill quarterly.

## 13.8 Restore testing

Restore test process:

```text
1. Create temporary restore directory.
2. Restore latest snapshot.
3. Verify expected files exist.
4. Validate Compose config from restored files.
5. Start one non-critical service using restored volume/config.
6. Restore database dump into temporary DB.
7. Run smoke tests.
8. Delete temporary restore environment.
9. Record result in docs/restore-tests.md.
```

---

---

# 14. Monitoring Architecture

## 14.1 Monitoring goals

- Detect failures before users do.
- Measure host resource pressure.
- Monitor container health.
- Monitor public and private endpoints.
- Alert on backup failure, disk usage, certificate expiration, tunnel failure.
- Keep enough retention for troubleshooting without exhausting PiKVM storage.

## 14.2 Monitoring architecture diagram

```text
Targets / Exporters
   +-- Node Exporter          host CPU/RAM/disk/network
   +-- cAdvisor               container CPU/RAM/restarts
   +-- Traefik metrics        routers/services/status
   +-- Blackbox Exporter      HTTP/TCP/DNS checks
   +-- cloudflared metrics    tunnel health if enabled
   +-- restic backup metrics  backup age/status
   +-- app /health endpoints
          |
          v
Prometheus
   +-- scrape configs
   +-- alert rules
   +-- retention policy
          |
          +-- Alertmanager --> ntfy/Gotify/email/Matrix
          |
          v
Grafana OSS
   +-- Host dashboard
   +-- Docker dashboard
   +-- Traefik dashboard
   +-- Backup dashboard
   +-- Cloudflare tunnel dashboard
   +-- SLO/service dashboard

Uptime Kuma
   +-- Public endpoint checks
   +-- Private Tailscale checks
   +-- Push monitors for backups/deploys
   +-- Status page optional
```

## 14.3 Recommended monitoring stack

| Component | Purpose |
|---|---|
| Prometheus | Metrics collection and alert rules |
| Grafana OSS | Dashboards and visualizations |
| Alertmanager | Alert routing/dedup/silence |
| Node Exporter | Host metrics |
| cAdvisor | Container metrics |
| Blackbox Exporter | Endpoint probing |
| Uptime Kuma | Simple uptime/status checks |
| Traefik metrics | Ingress visibility |
| Loki + Promtail/Alloy | Logs, covered in logging section |

## 14.4 Dashboards

Minimum dashboards:

1. **Host Overview**
   - CPU usage
   - load average
   - memory usage
   - disk usage
   - filesystem read-only state
   - network throughput
   - temperature if available

2. **Docker Overview**
   - container count
   - unhealthy containers
   - restart count
   - per-container CPU/memory
   - image versions

3. **Traefik Ingress**
   - request rate
   - error rate
   - latency percentiles
   - routers/services up
   - 4xx/5xx by service

4. **Cloudflare Tunnel**
   - tunnel process up
   - connector count
   - reconnects
   - edge location if available

5. **Backups**
   - last successful backup time
   - backup duration
   - repository size
   - prune/check result
   - restore-test age

6. **Security**
   - CrowdSec decisions
   - failed login counts
   - auth failures
   - suspicious IPs

7. **Service SLO**
   - availability
   - latency
   - error rate
   - saturation

## 14.5 Alerts

Critical alerts:

| Alert | Severity | Condition |
|---|---|---|
| Host down | critical | Node exporter unreachable |
| Disk almost full | critical | >90% for 10 min |
| Disk filling | warning | >80% for 30 min |
| Memory pressure | warning | sustained high memory / swap |
| Container unhealthy | critical | critical service unhealthy |
| Container restart loop | warning/critical | restarts > threshold |
| Traefik high 5xx | critical | 5xx rate above threshold |
| Public service down | critical | blackbox/Uptime Kuma failure |
| Cloudflare tunnel down | critical | cloudflared unhealthy |
| Backup failed | critical | no successful backup in 26h |
| Restore test stale | warning | no restore test in 35 days |
| Certificate expiring | warning/critical | <21 days / <7 days |
| Secret decryption failure | critical | deploy cannot decrypt required secrets |
| High auth failures | warning | failed logins spike |

## 14.6 Retention

For PiKVM V4, start conservative:

| Data | Retention |
|---|---|
| Prometheus metrics | 15-30 days locally |
| Loki logs | 7-14 days locally |
| Uptime Kuma history | 30-90 days depending storage |
| Backup logs | 90 days compressed |
| Security logs | 30-90 days depending risk/storage |

Future NAS/NUC can increase retention.

---

---

# 15. Logging Architecture

## 15.1 Logging goals

- Centralize container, system, proxy, auth, deploy, backup, and security logs.
- Keep local retention controlled.
- Make incidents diagnosable.
- Avoid filling disk.
- Protect sensitive data.

## 15.2 Logging architecture diagram

```text
Log Sources
   +-- Docker container stdout/stderr
   +-- Traefik access/error logs
   +-- cloudflared logs
   +-- Authelia/auth logs
   +-- systemd journal
   +-- SSH/auth logs
   +-- deployment logs
   +-- backup logs
   +-- security tools logs
          |
          v
Promtail or Grafana Alloy
   +-- labels: service, environment, host, stack
   +-- redaction where possible
   +-- shipping pipeline
          |
          v
Loki
   +-- retention policy
   +-- indexes
   +-- object/local storage
          |
          v
Grafana Explore / Dashboards / Alerts
```

## 15.3 Central logging stack

Recommended:

- Loki for log storage.
- Promtail or Grafana Alloy for collection.
- Grafana for searching and dashboards.

Promtail is stable but Grafana Alloy is the newer collector direction. For simplicity on PiKVM, Promtail is acceptable; for long-term consistency, consider Alloy.

## 15.4 Docker log rotation

Configure Docker daemon log rotation:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Rationale:

- Prevents container logs from filling disk.
- Loki receives logs for search.
- Local logs remain bounded.

## 15.5 Log retention

| Log type | Retention |
|---|---|
| Container logs in Docker json files | 3 files x 10 MB each by default |
| Loki app logs | 7-14 days on PiKVM |
| Security/auth logs | 30-90 days if storage allows |
| Deployment logs | 90 days or per release |
| Backup logs | 90 days plus latest summary |
| Traefik access logs | 7-30 days depending traffic |

## 15.6 Sensitive log handling

- Do not log secrets or tokens.
- Mask Authorization headers.
- Be careful with query strings.
- Avoid debug logging in production except temporarily.
- Restrict Loki/Grafana access.
- Back up only logs needed for compliance/troubleshooting.

---

---

# 16. Security Architecture

## 16.1 Security architecture diagram

```text
Public Internet
   |
   v
Cloudflare Edge
   +-- DNS proxy/tunnel route
   +-- optional WAF/rules/free protections
   +-- no direct home IP exposure
   |
   v
Cloudflare Tunnel
   +-- outbound-only connector
   |
   v
Traefik
   +-- explicit routers only
   +-- TLS
   +-- security headers
   +-- rate limiting
   +-- auth middleware
   +-- CrowdSec bouncer optional
   +-- dashboard protected
   |
   v
Docker Services
   +-- non-root users
   +-- read-only root FS where possible
   +-- dropped capabilities
   +-- no-new-privileges
   +-- isolated networks
   +-- pinned images
   +-- health checks
   |
   v
Host
   +-- firewall deny inbound except Tailscale/local needs
   +-- SSH restricted
   +-- automatic security updates with controlled reboot policy
   +-- fail2ban/CrowdSec where applicable
   +-- encrypted secrets
   +-- monitored backups
```

## 16.2 Least privilege

Apply least privilege everywhere:

- Users get only required access.
- CI deploy user can deploy only platform files.
- Containers run as non-root where supported.
- Volumes mounted read-only unless write is required.
- Docker socket not exposed directly.
- Tailscale ACLs restrict admin paths.
- Cloudflare tokens scoped narrowly.

## 16.3 Docker security

Recommended Compose security defaults where compatible:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true
tmpfs:
  - /tmp
restart: unless-stopped
```

Not every image supports read-only root filesystems or all capabilities dropped. Document exceptions per service.

## 16.4 Read-only containers

Use read-only root filesystem for:

- Static web apps.
- Exporters.
- Simple APIs.
- Reverse proxy if configured correctly.

Avoid or test carefully for:

- Databases.
- Apps that write cache to root.
- Apps requiring package/runtime writes.

## 16.5 Capability dropping

Default:

```yaml
cap_drop:
  - ALL
```

Add back only required capabilities. Examples:

| Capability | When needed |
|---|---|
| `NET_BIND_SERVICE` | Bind low ports inside container, usually avoid by using high internal ports |
| `NET_ADMIN` | VPN/network tools, avoid unless necessary |
| `CHOWN` | Some init scripts, avoid where possible |

## 16.6 Non-root containers

Prefer images that support `user:` or non-root by default.

For custom apps:

- Create non-root user in Dockerfile.
- Use writable directories owned by app user.
- Avoid privileged containers.

## 16.7 Network isolation

- Use dedicated networks per trust zone.
- Do not attach every service to `proxy`.
- Databases never attach to ingress network.
- Admin tools private by default.
- Monitoring can reach targets but targets should not reach monitoring unless necessary.

## 16.8 Authentication and authorization

- Public apps with sensitive data must require authentication.
- Admin dashboards require MFA.
- Prefer Authelia for forward auth.
- Use app-native role-based access where available.
- Use Tailscale ACLs for admin network authorization.

## 16.9 Secret management

- Use SOPS + age for secrets in Git.
- Decrypt only on trusted host or secure CI runner.
- Do not commit plaintext `.env` files.
- Use `.env.example` for documentation.
- Rotate tokens periodically.

## 16.10 Automatic updates

Recommendation:

- Enable OS security updates automatically if stable for your OS.
- Do not automatically update production containers without review.
- Use Renovate or Dependabot-like PRs for image updates.
- Use Watchtower in notification-only mode, not auto-update mode, for production.

## 16.11 Firewall

Host firewall policy:

- Deny inbound by default.
- Allow established/related.
- Allow Tailscale interface.
- Allow LAN SSH only if needed and restricted.
- Do not expose Traefik ports to LAN unless intentional.
- No WAN port forwards.

## 16.12 fail2ban and CrowdSec

### fail2ban

Useful for:

- SSH logs.
- Local auth logs.
- Simple brute-force blocking.

Less useful when:

- No direct public SSH exists.
- Public traffic source IP handling is behind Cloudflare unless real IPs are restored.

### CrowdSec

Useful for:

- Traefik log parsing.
- Community blocklists/decisions.
- Bouncer integration with Traefik.

Recommendation:

- Start with Traefik logs + CrowdSec once public apps exist.
- Ensure Cloudflare real client IP headers are handled correctly.

## 16.13 Container image scanning

Use:

- Trivy for vulnerabilities and misconfigurations.
- Grype as optional second scanner.
- Syft for SBOM.

Policy:

- Critical CVEs fail builds unless documented exception.
- Exceptions require expiration date.
- Pin image versions and preferably digests for critical services.

## 16.14 SBOM generation

Generate SBOM for custom images and important deployments:

- Syft SPDX or CycloneDX output.
- Store SBOM as release artifact.
- Use Grype/Trivy against SBOM where useful.

---

---

# 17. Secrets Management

## 17.1 Comparison

| Tool | Free/FOSS | Best for | Pros | Cons | Recommendation |
|---|---:|---|---|---|---|
| Environment variables | Yes | Simple local runtime | Easy, Compose-native | Easy to leak, weak lifecycle | Use only for non-sensitive or generated runtime from encrypted source |
| Docker Secrets | Yes, but best in Swarm | Secret files in containers | Better than env vars | Compose support differs; not full secret manager | Good if using Swarm; limited for plain Compose |
| SOPS | Yes | Encrypted secrets in Git | GitOps-friendly, supports age/GPG/KMS | Requires workflow discipline | Primary recommendation |
| age | Yes | Encryption backend | Simple modern key encryption | Key custody needed | Use with SOPS |
| Vault Community | Yes | Dynamic secrets, enterprise workflows | Powerful, audit, leases | Heavy, operational complexity | Future option, not day-one on PiKVM |
| Mozilla SOPS + age + direnv | Yes | Developer workflow | Excellent balance | Must avoid accidental export/logging | Recommended with care |

## 17.2 Best practice recommendation

Use **SOPS + age** as the default.

Store:

```text
secrets/
  production/
    cloudflare.sops.yaml
    traefik.sops.yaml
    authelia.sops.yaml
    grafana.sops.yaml
    restic.sops.yaml
  staging/
    ...
```

Runtime flow:

```text
Encrypted secrets in Git
   |
   v
Authorized deploy host decrypts with age key
   |
   v
Temporary runtime env files generated with strict permissions
   |
   v
Docker Compose starts services
   |
   v
Runtime env files cleaned or kept protected depending service needs
```

## 17.3 Key custody

- Store age private key on the production host with `0600` permissions.
- Keep offline encrypted backup of age private key.
- Keep printed recovery instructions, not printed secrets unless absolutely necessary and physically secured.
- Use separate keys for production and staging.
- Rotate keys if a device is lost.

## 17.4 What not to do

- Do not commit plaintext `.env.production`.
- Do not paste secrets into CI logs.
- Do not mount the whole secrets folder into every container.
- Do not reuse Cloudflare global API keys; use scoped tokens.
- Do not store restic password only on the machine being backed up.

---

---

# 18. Observability Model

## 18.1 Four pillars

| Pillar | Tooling | Purpose |
|---|---|---|
| Metrics | Prometheus, exporters, Grafana | Quantitative system state |
| Logs | Loki, Promtail/Alloy, Grafana | Event/context investigation |
| Traces | OpenTelemetry optional | Request flow across services |
| Health | Docker health checks, Uptime Kuma, Blackbox | Availability and readiness |

## 18.2 Metrics

Metrics answer:

- Is it up?
- Is it slow?
- Is it saturated?
- Is it erroring?
- Is capacity running out?

## 18.3 Logs

Logs answer:

- What happened?
- Which user/IP/service was involved?
- What changed before failure?
- Are there auth/security anomalies?

## 18.4 Traces

For a small homelab, traces are optional. Add OpenTelemetry later if you run custom apps or multiple microservices.

## 18.5 Health

Every service should define:

- Liveness: container process is alive.
- Readiness: service can receive traffic.
- Dependency health: DB/cache reachable if required.
- External availability: public route returns expected response.

## 18.6 Alerting

Alerts should be actionable:

- Include service name.
- Include symptom.
- Include likely cause.
- Include runbook link.
- Avoid noisy alerts.
- Use warning/critical severity.

## 18.7 Status pages

Use Uptime Kuma status pages for:

- personal visibility.
- family/internal users.
- simple public status page if desired.

Protect admin access; public status page should not reveal sensitive infrastructure details.

---

---

# 23. Documentation Standards

## 23.1 Required documentation types

| Doc type | Location | Purpose |
|---|---|---|
| Architecture overview | `docs/architecture/overview.md` | Big picture |
| Network diagram | `docs/architecture/network.md` | Network/security model |
| Service README | each stack folder | How service works and is operated |
| ADR | `docs/decisions/` | Record major decisions |
| Runbook | `docs/runbooks/` | Operational procedures |
| Troubleshooting | `docs/troubleshooting/` | Known failures and fixes |
| Disaster recovery | `docs/architecture/disaster-recovery.md` | Restore platform |
| Upgrade guide | per major service | Safe update process |
| Rollback guide | `docs/runbooks/rollback.md` | Restore previous release |

## 23.2 Architecture diagrams

Use ASCII diagrams in Markdown first. Optional future tools:

- Mermaid
- PlantUML
- Graphviz
- diagrams-as-code

All diagrams should include:

- data flow
- trust boundaries
- network names
- external dependencies
- failure domains

## 23.3 Service README template

Each service should document:

```text
# Service Name

## Purpose
## Owner
## Exposure
## URLs
## Networks
## Volumes
## Secrets
## Dependencies
## Health checks
## Backup/restore
## Upgrade procedure
## Rollback procedure
## Troubleshooting
## Security notes
```

## 23.4 Runbook standards

Each runbook should include:

- Symptoms.
- Impact.
- Immediate checks.
- Step-by-step remediation.
- Rollback/escape path.
- Verification.
- Post-incident follow-up.

## 23.5 Decision records

Use ADRs for decisions such as:

- Why Cloudflare Tunnel + Traefik.
- Why SOPS + age.
- Why restic.
- Why Authelia vs Authentik.
- Why Compose before Kubernetes/Nomad.

---

---

# 25. Disaster Recovery Plan

## 25.1 Disaster scenarios

| Scenario | Recovery approach |
|---|---|
| Single container failure | restart, rollback service |
| Bad deployment | automatic/manual rollback |
| Traefik config broken | restore previous proxy stack config |
| Cloudflare tunnel broken | Tailscale admin path, restore tunnel config/token |
| Host disk failure | rebuild host, restore repo/secrets/volumes |
| Lost age key | use offline backup key; if unavailable rotate all secrets |
| Database corruption | restore latest valid dump/snapshot |
| Compromised service | isolate, rotate secrets, restore clean version, review logs |
| Home internet outage | Tailscale unavailable from outside unless DERP/alternate path; use local recovery or VPS future |
| PiKVM hardware failure | restore to laptop/NUC/Raspberry Pi using backups |

## 25.2 Recovery time objectives

Suggested targets:

| Service class | RTO | RPO |
|---|---:|---:|
| Ingress/proxy | 30 minutes | config last commit |
| Monitoring | 1 hour | 24 hours acceptable |
| Public critical app | 1 hour | latest backup/pre-deploy snapshot |
| Media apps | 24 hours | 24 hours |
| Backups metadata | 4 hours | latest repository state |
| DNS filtering | 1 hour | latest config backup |

## 25.3 Full host rebuild process

```text
1. Prepare replacement host: PiKVM/laptop/NUC.
2. Install OS and update packages.
3. Install Docker CE and Compose plugin.
4. Install Tailscale and join tailnet with correct tags.
5. Configure firewall.
6. Clone homelab-platform repo.
7. Restore age private key from offline backup.
8. Decrypt required secrets.
9. Restore configs and Docker volumes from restic.
10. Restore database dumps.
11. Recreate Docker networks.
12. Start core stacks: proxy, tunnel, auth.
13. Start monitoring/logging/backups.
14. Start applications.
15. Verify Tailscale access.
16. Verify Cloudflare Tunnel route.
17. Run production smoke tests.
18. Document incident and recovery time.
```

## 25.4 Minimum emergency kit

Keep offline:

- This blueprint.
- Current runbooks.
- Backup repository password.
- age private key backup.
- Cloudflare recovery instructions.
- Tailscale recovery/admin instructions.
- List of critical domains and services.
- Latest known-good release tag.

---

---

# 28. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| PiKVM V4 resource limits | Monitoring/logging/CI may overload host | Keep retention low, avoid heavy CI on PiKVM, move heavy workloads to NUC later |
| Cloudflare dependency | Public ingress unavailable if Cloudflare/tunnel fails | Tailscale admin path, documented tunnel recovery, optional Tailscale Funnel emergency path |
| Tailscale account/control dependency | Private admin affected by account/control issues | Keep local console/OpenSSH fallback, evaluate Headscale later |
| Single-node failure | All services down | Encrypted backups, restore to laptop/NUC, future second node |
| Secret key loss | Cannot decrypt secrets | Offline age key backup, key custody runbook |
| Bad container update | Service outage | Pin versions, CI scan, manual deploy, rollback |
| Database migration failure | Data loss/outage | Pre-deploy DB dumps, backward-compatible migrations, manual DB rollback confirmation |
| Disk fills from logs/backups | Host instability | Docker log rotation, Loki retention, disk alerts, restic prune |
| Accidental public exposure | Security breach | Traefik `exposedByDefault=false`, network isolation, CI exposure tests |
| Raw Docker socket exposure | Host compromise | Avoid; use socket proxy if needed |
| Weak ACLs | Lateral movement | Tailscale ACL as code, regular review, tags |
| DNS outage | Clients lose resolution | Secondary resolver later, recovery runbook, avoid over-centralizing too soon |
| Backup silently broken | False sense of safety | Backup alerts, restic check, restore tests |
| Documentation drift | Recovery failure | Docs-as-code, review checklist, ADRs |
| Supply-chain vulnerabilities | Compromise/outage | Trivy/Grype scans, pinned images, SBOMs, update PRs |

---

---

# 30. Appendix: Operational Checklists

## 30.1 New service checklist

- [ ] Service has its own folder under `stacks/`.
- [ ] Service has README.
- [ ] Service uses pinned image version.
- [ ] Service runs non-root if possible.
- [ ] `no-new-privileges` enabled where compatible.
- [ ] Capabilities dropped where compatible.
- [ ] Read-only root filesystem where compatible.
- [ ] Health check defined.
- [ ] Restart policy defined.
- [ ] Only required Docker networks attached.
- [ ] No database attached to `proxy`.
- [ ] Traefik labels explicit if public.
- [ ] Auth middleware applied if sensitive.
- [ ] Secrets use SOPS.
- [ ] Volumes documented.
- [ ] Backup requirements documented.
- [ ] Monitoring/logging labels/config added.
- [ ] Rollback procedure documented.

## 30.2 Pre-deploy checklist

- [ ] Pull request reviewed.
- [ ] CI passed.
- [ ] Compose config validates.
- [ ] Secrets validation passed.
- [ ] Image scan reviewed.
- [ ] SBOM generated for custom images.
- [ ] Backup completed.
- [ ] Database dump completed if applicable.
- [ ] Rollback target known.
- [ ] Manual approval granted.

## 30.3 Post-deploy checklist

- [ ] Containers healthy.
- [ ] Traefik routers loaded.
- [ ] Public route works through Cloudflare.
- [ ] Private route works through Tailscale.
- [ ] Logs show no repeated errors.
- [ ] Metrics targets up.
- [ ] Uptime Kuma checks passing.
- [ ] Backup schedule still active.
- [ ] Release marked successful.
- [ ] Admin notified.

## 30.4 Monthly maintenance checklist

- [ ] Review disk usage.
- [ ] Review failed login/security logs.
- [ ] Review image update PRs.
- [ ] Review backup success.
- [ ] Perform sample restore.
- [ ] Check certificate expiry.
- [ ] Review Tailscale devices and ACLs.
- [ ] Review public routes.
- [ ] Update documentation if drift found.

## 30.5 Quarterly disaster recovery checklist

- [ ] Restore latest backup to temporary location.
- [ ] Validate Compose config from restored files.
- [ ] Restore one database dump to temporary DB.
- [ ] Start one non-critical restored service.
- [ ] Confirm age key backup is accessible.
- [ ] Confirm restic password backup is accessible.
- [ ] Review host rebuild runbook.
- [ ] Review emergency contacts/accounts.
- [ ] Record test result and fixes.

---

---

# 33. Daily Backup and One-Shot Git Checkpoint Restore

The backup and restore experience should feel simple and intuitive:

```bash
make checkpoint
make backup
make restore CHECKPOINT=checkpoint-2026-08-04-prod DRY_RUN=1
make restore CHECKPOINT=checkpoint-2026-08-04-prod CONFIRM_RESTORE=checkpoint-2026-08-04-prod
```

The operator should not need to remember which Docker volumes, database dumps, config files, certificate files, image versions, or secrets belong together. A **Git checkpoint** ties them together in one manifest.

## 33.1 Core idea

Git stores platform code and manifests. Restic stores data. The checkpoint manifest links them.

```text
Git checkpoint tag / commit
   |
   +-- Compose files
   +-- Traefik/cloudflared configs
   +-- SOPS-encrypted secrets
   +-- restore manifest YAML
   |      +-- restic snapshot IDs
   |      +-- Docker volume map
   |      +-- database dump references
   |      +-- image tags/digests
   |      +-- host/runtime metadata
   |      +-- validation evidence
   |
   v
Restic encrypted repository
   +-- Docker volume snapshots
   +-- bind-mount data snapshots
   +-- database dumps
   +-- ACME/certificates
   +-- selected logs
```

Git should not contain raw Docker volume data, decrypted secrets, database dumps, or certificates. Git contains the checkpoint manifest and encrypted config/secrets only. Restic contains the encrypted data snapshots.

## 33.2 What a checkpoint means

A checkpoint is a named, restorable platform state.

Example checkpoint ID:

```text
checkpoint-2026-08-04-0200-prod
```

It should identify:

- Git commit SHA.
- Optional Git tag.
- Environment name, such as `local`, `staging`, `prod`, or `laptop-prod`.
- Hostname and architecture.
- Rendered Compose config hash.
- Image tags and digests.
- Restic repository ID.
- Restic snapshot IDs.
- Docker volume map.
- Database dump files and checksums.
- SOPS-encrypted secret file versions.
- Certificate/ACME backup reference.
- Validation and health-check status.

## 33.3 Recommended checkpoint files

```text
releases/
  checkpoints/
    checkpoint-2026-08-04-0200-prod.yaml
    checkpoint-2026-08-04-0200-prod.sha256
    latest-prod.txt

scripts/
  backup/
    checkpoint.sh
    backup.sh
    backup-volumes.sh
    backup-databases.sh
    backup-configs.sh
    verify-backup.sh
    list-checkpoints.sh
    restore-checkpoint.sh
    restore-volume.sh
    restore-database.sh
    restore-test.sh

docs/
  runbooks/
    one-shot-restore.md
    daily-backup.md
```

## 33.4 Checkpoint manifest example

This is a conceptual manifest. It should be generated automatically by `scripts/backup/checkpoint.sh`.

```yaml
apiVersion: homelab/v1
kind: RestoreCheckpoint
metadata:
  id: checkpoint-2026-08-04-0200-prod
  createdAt: "2026-08-04T02:00:00-04:00"
  environment: prod
  host: laptop-prod-01
  architecture: arm64
  createdBy: systemd-timer

git:
  repository: git@github.com:example/homelab-platform.git
  branch: main
  commit: abcdef1234567890abcdef1234567890abcdef12
  tag: checkpoint-2026-08-04-0200-prod
  dirtyTreeAllowed: false

compose:
  projectName: homelab
  files:
    - compose/production.yml
    - compose/networks.yml
  renderedConfig: releases/rendered/production-checkpoint-2026-08-04-0200-prod.yml
  renderedConfigSha256: PLACEHOLDER_SHA256

images:
  - service: traefik
    image: traefik:v3.1.0
    digest: sha256:PLACEHOLDER
  - service: cloudflared
    image: cloudflare/cloudflared:2026.8.0
    digest: sha256:PLACEHOLDER

secrets:
  backend: sops-age
  encryptedFiles:
    - secrets/production/cloudflare.sops.yaml
    - secrets/production/traefik.sops.yaml
    - secrets/production/restic.sops.yaml
  ageRecipientFingerprint: PLACEHOLDER_PUBLIC_FINGERPRINT

restic:
  repositoryName: homelab-prod
  repositoryId: PLACEHOLDER_RESTIC_REPOSITORY_ID
  snapshots:
    configs: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    dockerVolumes: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    databases: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    certificates: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    logs: PLACEHOLDER_RESTIC_SNAPSHOT_ID

volumes:
  namedVolumes:
    - name: grafana-data
      service: grafana
      restorePath: /var/lib/docker/volumes/grafana-data/_data
      snapshotGroup: dockerVolumes
    - name: prometheus-data
      service: prometheus
      restorePath: /var/lib/docker/volumes/prometheus-data/_data
      snapshotGroup: dockerVolumes
  bindMounts:
    - service: traefik
      hostPath: /srv/homelab/stacks/proxy/traefik
      snapshotGroup: configs

databases:
  dumps:
    - service: postgres-example
      engine: postgres
      dumpPath: backups/databases/postgres-example.sql.gz
      sha256: PLACEHOLDER_SHA256
      snapshotGroup: databases

certificates:
  acmeFile: stacks/proxy/traefik/acme/acme.json
  snapshotGroup: certificates

validation:
  backupCompleted: true
  resticCheckCompleted: true
  composeConfigValidated: true
  healthChecksPassedBeforeBackup: true
  restoreTestRequired: true
  restoreTestStatus: pending
```

## 33.5 Daily backup schedule

Recommended daily flow:

```text
02:00 daily
   |
   v
Preflight
   +-- confirm disk space
   +-- confirm restic repository reachable
   +-- confirm Git tree clean or explicitly allow dirty=false
   +-- confirm Docker reachable
   +-- confirm SOPS encrypted files present
   |
   v
Create database dumps
   +-- pg_dump / mysqldump / sqlite safe copy
   |
   v
Backup configs, encrypted secrets, volumes, DB dumps, certs, selected logs
   |
   v
Run restic forget/prune policy
   |
   v
Run restic check or lightweight verify
   |
   v
Generate checkpoint manifest
   |
   v
Commit manifest and optionally create Git tag
   |
   v
Push Git checkpoint metadata
   |
   v
Send notification and update monitoring
```

Recommended schedule:

| Time | Task |
|---|---|
| Daily 02:00 | Full logical backup + volume backup + checkpoint manifest |
| Daily 02:30 | Lightweight restic check / snapshot verify |
| Weekly Sunday 03:00 | Full restic repository check |
| Weekly Sunday 04:00 | Restore-test one non-critical service to temporary path |
| Monthly | Full one-shot restore drill to temporary host/path |

## 33.6 What gets backed up daily

| Data | Backup location | Notes |
|---|---|---|
| Git repository | Git remote + restic config backup | Git remote alone is not enough. |
| Compose files | Git + restic | Rendered Compose config stored as artifact/checkpoint. |
| Traefik/cloudflared configs | Git + restic | Secrets excluded or encrypted only. |
| SOPS-encrypted secrets | Git + restic | Safe to store encrypted copies. |
| Decrypted runtime secrets | Avoid; restic only if unavoidable | Prefer regenerate from SOPS. |
| Docker named volumes | restic | Use volume map in checkpoint. |
| Bind-mount data | restic | Prefer `/srv/homelab/data/<service>` for simplicity. |
| Databases | logical dump + restic | Dump before volume backup. |
| ACME/certificates | restic | Restore permissions must be strict. |
| Logs | Loki retention + selected restic | Do not over-backup noisy logs. |
| Release metadata | Git + restic | Needed for rollback and audit. |

## 33.7 Prefer intuitive bind-mount layout

For easy restore, prefer a consistent data layout instead of anonymous or hard-to-find mounts.

Recommended host layout:

```text
/srv/homelab/
  repo/                         # Git checkout
  data/
    grafana/
    prometheus/
    loki/
    authelia/
    traefik/
    postgres-example/
  backups/
    database-dumps/
    restore-tests/
  runtime/
    env/                        # generated env files, permissions 0600
    rendered-compose/
  logs/
```

Named Docker volumes are still acceptable, but every named volume must appear in the checkpoint manifest. Anonymous volumes should be avoided for production services.

## 33.8 Simple Makefile interface

The operator should have a small set of obvious commands.

```makefile
.PHONY: checkpoint backup restore restore-dry-run list-checkpoints verify-backup restore-test

checkpoint:
	./scripts/backup/checkpoint.sh

backup:
	./scripts/backup/backup.sh

list-checkpoints:
	./scripts/backup/list-checkpoints.sh

restore-dry-run:
	./scripts/backup/restore-checkpoint.sh --checkpoint $(CHECKPOINT) --dry-run

restore:
	./scripts/backup/restore-checkpoint.sh --checkpoint $(CHECKPOINT)

verify-backup:
	./scripts/backup/verify-backup.sh

restore-test:
	./scripts/backup/restore-test.sh
```

Expected usage:

```bash
make list-checkpoints
make restore-dry-run CHECKPOINT=checkpoint-2026-08-04-0200-prod
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod
```

## 33.9 One-shot restore workflow

The restore command should be safe by default.

```text
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod DRY_RUN=1
   |
   v
Load checkpoint manifest
   |
   v
Verify Git commit/tag exists
   |
   v
Verify restic repository reachable
   |
   v
Verify all snapshot IDs exist
   |
   v
Verify SOPS encrypted secrets exist
   |
   v
Render restore plan
   |
   v
Stop unless explicit confirmation is supplied
```

Real restore:

```text
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod CONFIRM_RESTORE=checkpoint-2026-08-04-0200-prod
   |
   v
Preflight and confirmation
   |
   v
Stop current stack safely
   |
   v
Checkout Git checkpoint commit/tag
   |
   v
Decrypt/generate runtime secrets locally
   |
   v
Restore configs and certificates
   |
   v
Restore Docker volumes and bind mounts
   |
   v
Restore database dumps if applicable
   |
   v
Pull pinned images
   |
   v
Render Compose config
   |
   v
Start core services
   |
   v
Start dependent services
   |
   v
Run health checks
   |
   v
Run traffic checks
   |
   v
Mark restore successful or stop for manual recovery
```

## 33.10 Restore safety gates

The restore script must refuse to proceed unless:

- `CHECKPOINT` is provided.
- Checkpoint manifest exists.
- Checkpoint manifest checksum matches.
- Git commit/tag exists.
- Restic repository is reachable.
- Referenced restic snapshots exist.
- Target restore path is known.
- Current state is snapshotted before destructive restore.
- User passes explicit confirmation for real restore.
- For database overwrite, user passes an additional database confirmation.

Example confirmation pattern:

```bash
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod CONFIRM_RESTORE=checkpoint-2026-08-04-0200-prod
```

For destructive database restore:

```bash
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod CONFIRM_RESTORE=checkpoint-2026-08-04-0200-prod CONFIRM_DATABASE_RESTORE=I_UNDERSTAND_DATABASE_OVERWRITE
```

## 33.11 Restore modes

| Mode | Command | Purpose |
|---|---|---|
| Dry run | `make restore-dry-run CHECKPOINT=...` | Show what would be restored. |
| Config only | `make restore-config CHECKPOINT=...` | Restore Git/config/secrets templates only. |
| One service | `make restore-service CHECKPOINT=... SERVICE=grafana` | Restore one service volume/config. |
| Full stack | `make restore CHECKPOINT=...` | Restore complete platform state. |
| Test restore | `make restore-test CHECKPOINT=...` | Restore to temp path/project. |

## 33.12 Database handling

Database volumes alone are not enough for reliable backups. Use logical dumps.

| Database | Backup method | Restore method |
|---|---|---|
| Postgres | `pg_dump` or `pg_dumpall` | restore into fresh container/db |
| MariaDB/MySQL | `mysqldump` or `mariadb-dump` | restore into fresh container/db |
| SQLite | app-aware stop/lock and file copy | restore DB file with ownership fix |
| Redis | RDB/AOF copy after save | restore file and restart |

The checkpoint manifest should record database dump path, engine, compression, checksum, and restic snapshot group.

## 33.13 Volume handling

Docker volume restore must be predictable.

Rules:

- Avoid anonymous volumes.
- Prefer named volumes or clear bind mounts.
- Every persistent volume appears in the checkpoint manifest.
- Volumes are restored before dependent services start.
- Ownership and permissions are validated after restore.
- Databases restore from logical dumps unless explicitly using volume-level restore for a known-safe engine.

## 33.14 Daily backup verification

A daily backup is not successful just because the command exited. It must verify:

- Restic snapshot created.
- Database dumps created and checksummed.
- Checkpoint manifest generated.
- Manifest checksum generated.
- Git checkpoint metadata committed or stored.
- Optional Git tag created.
- `restic snapshots` sees the new snapshots.
- `restic check` or lightweight verify passes according to schedule.
- Uptime Kuma/ntfy/Gotify notification sent.

## 33.15 Restore test verification

Weekly restore test should:

1. Create a temporary restore directory.
2. Restore selected config files.
3. Restore one small volume or service dataset.
4. Restore one database dump to a temporary container if available.
5. Run `docker compose config` against restored config.
6. Start a non-conflicting test Compose project if safe.
7. Run health/smoke checks.
8. Delete temporary resources.
9. Record result in `docs/runbooks/restore-tests.md` or `releases/checkpoints/restore-test-log.md`.

## 33.16 Git checkpoint retention

Recommended retention:

| Checkpoint type | Retention |
|---|---|
| Daily checkpoint manifests | 30-60 days in Git, or longer if small |
| Weekly checkpoint tags | 12 weeks |
| Monthly checkpoint tags | 12-24 months |
| Pre-deploy checkpoints | Keep at least last 20 deploys |
| Major upgrade checkpoints | Keep indefinitely or until superseded |

Restic retention can be longer than Git manifest retention, but do not delete manifests needed to understand restic snapshots that still exist.

## 33.17 CI/CD integration

GitHub Actions should validate backup and restore scripts without touching production data.

Required CI checks:

- Shellcheck backup scripts.
- Validate checkpoint manifest schema.
- Validate Makefile targets exist.
- Run restore dry-run against a fixture checkpoint.
- Ensure restore defaults to dry-run/safe behavior.
- Ensure destructive restore requires explicit confirmation.
- Ensure artifacts do not contain secrets.

Suggested fixture:

```text
tests/fixtures/checkpoints/checkpoint-fixture.yaml
tests/fixtures/restic-snapshots/sample-snapshots.txt
```

## 33.18 One-shot restore definition of done

The one-shot restore system is not done until:

- `make checkpoint` creates a manifest.
- `make backup` creates restic snapshots.
- `make list-checkpoints` shows available checkpoints.
- `make restore-dry-run CHECKPOINT=...` prints a safe restore plan.
- `make restore CHECKPOINT=...` refuses to run without explicit confirmation.
- Volume restore is tested with at least one non-critical service.
- Database restore is tested with a fixture or non-critical database.
- Permissions are validated after restore.
- Health checks run after restore.
- Restore test results are documented.
- CI validates scripts and fixture restore behavior.

---

---
