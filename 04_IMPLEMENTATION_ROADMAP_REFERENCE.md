# Implementation Roadmap, Technology Stack, and Prompt Reference

> Split from `HOMELAB_PLATFORM_BLUEPRINT.md` on 2026-08-04. The original giant file is retained as an archive/source reference.

Implementation reference: directory structure, technology comparisons, stack choices, scaling roadmap, phases, small-model prompts, and final architecture.

## Local Table of Contents

- [19. Production Directory Structure](#19-production-directory-structure)
- [20. Technology Comparison Tables](#20-technology-comparison-tables)
- [21. Recommended Technology Stack](#21-recommended-technology-stack)
- [24. Future Expansion Roadmap](#24-future-expansion-roadmap)
- [26. Complete Implementation Phases](#26-complete-implementation-phases)
- [27. Small-Model Session Prompts](#27-small-model-session-prompts)
- [29. Final Recommended Architecture](#29-final-recommended-architecture)
- [End State](#end-state)

---

# 19. Production Directory Structure

## 19.1 Directory tree

```text
homelab-platform/
  README.md
  CHANGELOG.md
  LICENSE
  .editorconfig
  .gitignore
  .sops.yaml
  Makefile

  docs/
    architecture/
      overview.md
      network.md
      security.md
      tailscale.md
      traefik.md
      backups.md
      monitoring.md
      logging.md
      disaster-recovery.md
      scaling-roadmap.md
    runbooks/
      deploy.md
      rollback.md
      restore.md
      tunnel-outage.md
      tailscale-recovery.md
      disk-full.md
      certificate-expiry.md
      database-restore.md
    decisions/
      ADR-0001-platform-principles.md
      ADR-0002-cloudflare-tunnel-traefik.md
      ADR-0003-sops-age-secrets.md
      ADR-0004-restic-backups.md
    diagrams/
      architecture.ascii.md
      network.ascii.md
      tailscale-modes.ascii.md
    troubleshooting/
      common-failures.md
      docker.md
      traefik.md
      dns.md
      tailscale.md

  infra/
    host/
      README.md
      sysctl.d/
      nftables/
      ufw/
      systemd/
        backup.service
        backup.timer
        maintenance.service
        maintenance.timer
      docker/
        daemon.json
    tailscale/
      README.md
      policy.hujson
      examples/
    cloudflare/
      README.md
      tunnel/
        config.yml.template
      dns/
        records.md
    security/
      README.md
      crowdsec/
      fail2ban/
      hardening-checklist.md

  compose/
    production.yml
    staging.yml
    networks.yml
    volumes.yml
    override.example.yml
    profiles/
      public.yml
      monitoring.yml
      backups.yml
      media.yml
      devtools.yml

  stacks/
    proxy/
      README.md
      compose.yml
      traefik/
        static.yml
        dynamic/
          middlewares.yml
          tls.yml
          security-headers.yml
          rate-limits.yml
      cloudflared/
        config.yml.template
    auth/
      README.md
      compose.yml
      authelia/
        configuration.yml.template
    monitoring/
      README.md
      compose.yml
      prometheus/
        prometheus.yml
        rules/
      grafana/
        provisioning/
          dashboards/
          datasources/
      alertmanager/
        alertmanager.yml.template
      uptime-kuma/
    logging/
      README.md
      compose.yml
      loki/
        loki.yml
      promtail/
        promtail.yml
    backups/
      README.md
      compose.yml
      restic/
        backup.sh
        restore.sh
        check.sh
        forget-prune.sh
    dns/
      README.md
      compose.yml
      adguardhome/
      pihole/
      unbound/
    apps/
      example-public-app/
        README.md
        compose.yml
        config/
      example-private-app/
        README.md
        compose.yml
    media/
      README.md
      compose.yml
    devtools/
      README.md
      compose.yml
      forgejo/
      woodpecker/

  configs/
    README.md
    common/
    production/
    staging/
    templates/

  secrets/
    README.md
    production/
      cloudflare.sops.yaml
      traefik.sops.yaml
      authelia.sops.yaml
      grafana.sops.yaml
      restic.sops.yaml
    staging/
      example.sops.yaml

  scripts/
    README.md
    bootstrap/
      00-check-host.sh
      01-install-docker.sh
      02-create-networks.sh
      03-install-tailscale.sh
      04-setup-firewall.sh
    deploy/
      deploy.sh
      preflight.sh
      healthcheck.sh
      verify-traffic.sh
      rollback.sh
    backup/
      backup.sh
      restore.sh
      restore-test.sh
    validate/
      validate-compose.sh
      validate-traefik.sh
      validate-cloudflared.sh
      validate-secrets.sh
      validate-networks.sh
      validate-permissions.sh
    maintenance/
      update-os.sh
      prune-docker.sh
      rotate-logs.sh

  ci/
    README.md
    github-actions/
      validate.yml
      release.yml
      deploy.yml
    forgejo-actions/
      validate.yml
      deploy.yml
    woodpecker/
      .woodpecker.yml
    scripts/
      ci-lint.sh
      ci-test.sh
      ci-scan.sh

  templates/
    service/
      README.md.template
      compose.yml.template
      env.example.template
      healthcheck.sh.template
    traefik/
      labels.public.yml.template
      labels.private.yml.template
    docs/
      runbook.template.md
      adr.template.md
      service-readme.template.md

  tests/
    README.md
    compose/
      test-compose-config.sh
    traefik/
      test-routers.sh
      test-middlewares.sh
    cloudflare/
      test-tunnel-config.sh
    networking/
      test-network-isolation.sh
    backups/
      test-restore.sh
    security/
      test-no-plaintext-secrets.sh
      test-permissions.sh

  releases/
    README.md
    .gitkeep
```

## 19.2 Directory purposes

| Directory | Purpose |
|---|---|
| `docs/` | Human documentation, architecture, runbooks, ADRs |
| `infra/` | Host-level and external platform configuration |
| `compose/` | Top-level Compose entrypoints and shared definitions |
| `stacks/` | Modular service stacks by domain |
| `configs/` | Environment-specific non-secret configuration |
| `secrets/` | SOPS-encrypted secret files only |
| `scripts/` | Bootstrap, deploy, validate, backup, maintenance automation |
| `ci/` | CI workflow definitions and helper scripts |
| `templates/` | Reusable templates for new services/docs |
| `tests/` | Automated validation scripts |
| `releases/` | Generated release metadata, not bulky artifacts |

---

---

# 20. Technology Comparison Tables

## 20.1 Reverse proxy

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Traefik | Docker-native, labels, ACME, middleware, metrics | Dynamic config complexity | Recommended |
| Caddy | Very simple TLS, great UX | Docker discovery less rich without plugins | Good alternative |
| Nginx Proxy Manager | Easy UI | Less GitOps-native, UI-driven drift | Avoid for this goal |
| HAProxy | Very powerful/stable | More manual config | Good for advanced LB later |

## 20.2 Private network / VPN

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Tailscale | Easy WireGuard mesh, ACLs, MagicDNS, SSH | Coordination service dependency | Recommended per requirements |
| Headscale | FOSS Tailscale control server | Operate yourself, feature differences | Future lock-in reduction option |
| WireGuard raw | Fully FOSS, simple | Manual keys/routes | Good fallback |
| Netbird | FOSS option | Extra platform operation | Evaluate later |

## 20.3 CI/CD

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| GitHub Actions | Easy, strong ecosystem | SaaS dependency/free tier limits | Good starter |
| Forgejo Actions | Self-hosted, FOSS | Operate runners | Long-term recommended |
| Gitea Actions | Lightweight self-hosted | Similar ops burden | Good option |
| Woodpecker CI | Lightweight, FOSS | Different syntax | Strong self-hosted recommendation |
| Drone CE | Container-native | CE concerns | Not first choice |

## 20.4 Monitoring

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Prometheus | Standard, powerful | Pull config/retention tuning | Recommended |
| Grafana OSS | Excellent dashboards | Needs auth/security | Recommended |
| Uptime Kuma | Very easy uptime checks | Not full metrics system | Recommended supplement |
| Netdata | Quick host observability | Less GitOps-focused | Optional |
| Zabbix | Enterprise monitoring | Heavier | Future option |

## 20.5 Logging

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Loki | Good with Grafana, efficient labels | Query model differs from full text search | Recommended |
| Elasticsearch/OpenSearch | Powerful search | Heavy for PiKVM | Avoid initially |
| Graylog | Good UI | Heavy | Avoid initially |
| File logs only | Simple | Poor centralized troubleshooting | Insufficient |

## 20.6 Backups

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| restic | Encrypted, simple, many backends | Forget/prune/check discipline needed | Recommended |
| BorgBackup | Excellent dedupe, mature | Best over SSH/local, fewer backend types | Strong alternative |
| Kopia | Nice features/UI | More moving parts | Optional |
| rsync only | Simple | No built-in encryption/versioning | Not sufficient alone |

## 20.7 Secrets

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| SOPS + age | GitOps-friendly, FOSS | Key management required | Recommended |
| Docker Secrets | Better runtime secret mount | Best with Swarm | Optional/limited Compose |
| Vault Community | Powerful | Heavy operational burden | Future only |
| Plain env files | Easy | Risky | Avoid for real secrets |

## 20.8 DNS filtering

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| AdGuard Home | Modern UI, policies | Additional service dependency | Recommended if new |
| Pi-hole | Mature community | Less modern policy model | Good alternative |
| Unbound | Recursive resolver | Not ad filtering by itself | Pair with either |

---

---

# 21. Recommended Technology Stack

## 21.1 Day-one stack

| Layer | Tool |
|---|---|
| Runtime | Docker CE + Docker Compose plugin |
| Public edge | Cloudflare DNS + Cloudflare Tunnel |
| Reverse proxy | Traefik |
| Private access | Tailscale |
| Secrets | SOPS + age |
| Monitoring | Prometheus, Grafana OSS, Node Exporter, cAdvisor, Alertmanager |
| Uptime | Uptime Kuma |
| Logging | Loki + Promtail/Alloy |
| Backups | restic |
| Security scanning | Trivy + Syft |
| Auth | Authelia |
| DNS filtering | AdGuard Home or Pi-hole, optional Unbound |
| Notifications | ntfy or Gotify |
| CI starter | GitHub Actions or local scripts |
| CI long-term | Forgejo + Woodpecker CI or Forgejo Actions |

## 21.2 Why this stack

- Compose is appropriate for a single PiKVM today.
- Traefik scales naturally from Compose to Swarm/Kubernetes-style ingress concepts.
- Tailscale gives secure private admin without exposing ports.
- SOPS + age makes secrets GitOps-compatible without heavy infrastructure.
- Prometheus/Grafana/Loki are standard and portable.
- restic gives encrypted backups with simple restore.
- Forgejo/Woodpecker provide a future no-SaaS workflow.

---

---

# 24. Future Expansion Roadmap

## 24.1 One node -> multi-node roadmap

### Stage A: Single PiKVM V4

- Docker Compose.
- Cloudflare Tunnel.
- Traefik.
- Tailscale.
- Monitoring/logging/backups.

### Stage B: Add NAS

- Move backup target to NAS.
- Move media storage to NAS.
- Add NAS monitoring.
- Add NAS as Tailscale node.
- Optional second DNS resolver.

### Stage C: Add Intel NUC / mini PC

- Move heavier apps to NUC.
- Keep PiKVM for KVM/admin/infrastructure or lightweight services.
- Add second cloudflared connector.
- Add second Traefik instance or keep one ingress node.
- Use Tailscale subnet routing on both.

### Stage D: Multi-host Docker

Options:

- Continue separate Compose per host with shared Git repo.
- Use Docker contexts over SSH.
- Use Ansible for orchestration.
- Consider Docker Swarm if simple multi-node service scheduling is desired.

### Stage E: Nomad migration

Nomad is a strong intermediate step:

- Lightweight compared to Kubernetes.
- Good for mixed workloads.
- Consul optional for service discovery.
- Traefik can integrate.

### Stage F: Kubernetes migration

Kubernetes is appropriate if:

- You need declarative scheduling.
- You want Helm/Kustomize ecosystem.
- You have at least 3 stable nodes for HA control plane or accept non-HA k3s.
- You are ready for storage/network complexity.

Suggested distro:

- k3s for lightweight homelab.
- Talos Linux for immutable cluster later.

## 24.2 High availability expansion

| Component | Single-node today | HA future |
|---|---|---|
| Cloudflare Tunnel | one connector | multiple connectors on different hosts |
| Traefik | one instance | active/active or active/passive ingress nodes |
| DNS filtering | one AdGuard/Pi-hole | two resolvers |
| Monitoring | one Prometheus | remote write or second monitoring node |
| Logs | one Loki | NAS/object storage backend or second Loki |
| Backups | local + USB/NAS | 3-2-1 with offsite self-hosted target |
| Databases | local volumes | replicated DB or app-specific HA |
| Tailscale subnet router | PiKVM | two route advertisers |
| Exit node | optional PiKVM | NUC + VPS alternatives |

## 24.3 Load balancing

Near-term:

- Cloudflare Tunnel can route to one or more local services.
- Traefik can load balance between multiple container instances on a host.

Future:

- Multiple Traefik nodes.
- Keepalived/VRRP on LAN if using direct LAN VIP.
- Cloudflare Load Balancing is paid, so avoid relying on it.
- DNS failover can be manual or scripted.

## 24.4 Distributed storage

Avoid distributed storage too early.

Options later:

| Tool | Use case | Notes |
|---|---|---|
| NFS from NAS | Simple shared storage | Easy but single NAS dependency |
| Samba | Media/user shares | Not ideal for app databases |
| Syncthing | Config/file sync | Not database-safe |
| Longhorn | Kubernetes block storage | Needs multiple nodes/disks |
| Ceph | Serious distributed storage | Heavy for small homelab |
| MinIO | S3-compatible object storage | Good backup/artifact target |

## 24.5 Multiple PiKVMs

If adding multiple PiKVMs:

- Each joins Tailscale with tag `tag:pikvm`.
- Keep PiKVM device management private.
- Do not expose PiKVM web UI publicly unless strongly justified.
- Use naming: `pikvm-rack-01`, `pikvm-rack-02`.
- Monitor reachability and certificate status.

## 24.6 Multiple Cloudflare tunnels

Patterns:

1. **Single tunnel, multiple connectors**
   - Same tunnel token on multiple hosts.
   - Cloudflare balances connector availability.

2. **One tunnel per environment**
   - `prod-tunnel`, `staging-tunnel`.
   - Cleaner separation.

3. **One tunnel per site**
   - home, VPS, remote lab.

Recommendation:

- Start with one production tunnel.
- Add a second connector on NUC/NAS later.
- Use separate staging tunnel if staging becomes public.

---

---

# 26. Complete Implementation Phases

These phases are designed so each phase can be completed by a smaller model or in a focused implementation session.

## Phase 0: Planning and inventory

### Goal

Create the source-of-truth repo structure and document current hardware, domains, IP ranges, and desired services.

### Tasks

1. Create `homelab-platform` repository.
2. Add base directory structure.
3. Add `README.md` with goals and assumptions.
4. Document hardware inventory.
5. Document current network ranges.
6. Choose production domain and internal domain.
7. Choose naming convention.
8. Create ADR for platform principles.

### Deliverables

- Repo skeleton.
- Inventory document.
- Network assumptions document.
- Initial ADRs.

### Done criteria

- Repository has all top-level directories.
- README states no direct exposed ports.
- Hardware and domain assumptions are documented.

---

## Phase 1: Host baseline hardening

### Goal

Prepare PiKVM V4 or laptop host as a stable Docker platform.

### Tasks

1. Update OS.
2. Install Docker CE and Compose plugin.
3. Configure Docker log rotation.
4. Create deployment user.
5. Configure SSH restrictions.
6. Configure firewall deny-by-default.
7. Add base system monitoring packages.
8. Add systemd maintenance timers.
9. Document host bootstrap.

### Deliverables

- `infra/host/docker/daemon.json`
- firewall config
- bootstrap scripts
- host hardening runbook

### Done criteria

- Docker works.
- Compose works.
- Firewall blocks unwanted inbound access.
- Logs rotate.
- Host can be administered safely.

---

## Phase 2: Tailscale private administration

### Goal

Establish private admin plane.

### Tasks

1. Install Tailscale on host OS.
2. Join tailnet with stable hostname.
3. Enable MagicDNS.
4. Define device tags.
5. Draft ACL policy.
6. Enable Tailscale SSH or restrict OpenSSH to Tailscale.
7. Test admin access from laptop and phone.
8. Document normal and emergency workflows.

### Deliverables

- `infra/tailscale/policy.hujson`
- Tailscale runbook
- emergency access runbook

### Done criteria

- Admin can SSH over Tailscale.
- Non-admin access is denied by ACL.
- MagicDNS resolves host.

---

## Phase 3: Docker networks and base Compose framework

### Goal

Create modular network and Compose foundation.

### Tasks

1. Define external Docker networks.
2. Create `compose/networks.yml`.
3. Create stack template.
4. Add validation script for networks.
5. Document network purpose and allowed communication.

### Deliverables

- network definitions
- service template
- network docs

### Done criteria

- Required networks exist.
- Compose config validates.
- No service can be exposed by default.

---

## Phase 4: Traefik reverse proxy

### Goal

Deploy Traefik as internal ingress controller.

### Tasks

1. Create proxy stack.
2. Configure Traefik static config.
3. Configure Docker provider with `exposedByDefault=false`.
4. Add dynamic middleware files.
5. Add security headers.
6. Add rate limits.
7. Protect dashboard.
8. Enable metrics endpoint internally.
9. Add test service route.
10. Validate routing.

### Deliverables

- `stacks/proxy/compose.yml`
- Traefik config
- middleware config
- proxy runbook

### Done criteria

- Traefik starts.
- Test service routes only when explicitly labeled.
- Dashboard is protected/private.
- Metrics are available internally.

---

## Phase 5: Cloudflare Tunnel public ingress

### Goal

Connect public DNS to Traefik without exposing ports.

### Tasks

1. Create Cloudflare tunnel.
2. Store tunnel credentials securely.
3. Configure cloudflared stack.
4. Route `*.example.com` or selected hosts to Traefik.
5. Ensure final ingress rule is safe default.
6. Test public route.
7. Document tunnel recovery.

### Deliverables

- cloudflared config template
- encrypted tunnel secrets
- DNS/tunnel docs

### Done criteria

- Public test route works through Cloudflare Tunnel.
- No router ports are forwarded.
- Tunnel credentials are not plaintext in Git.

---

## Phase 6: Secrets management with SOPS + age

### Goal

Make secrets GitOps-compatible and secure.

### Tasks

1. Install SOPS and age.
2. Generate production age key.
3. Create `.sops.yaml`.
4. Create encrypted secret files.
5. Add decrypt/render script.
6. Add secret validation CI check.
7. Document key backup and rotation.

### Deliverables

- `.sops.yaml`
- `secrets/production/*.sops.yaml`
- validation script
- secrets runbook

### Done criteria

- Secrets decrypt only on authorized host.
- No plaintext secrets in Git.
- Recovery key is backed up offline.

---

## Phase 7: Authentication layer

### Goal

Protect admin and sensitive web apps.

### Tasks

1. Deploy Authelia.
2. Configure users, password hashing, sessions.
3. Configure MFA.
4. Add Traefik forward-auth middleware.
5. Protect Traefik dashboard/Grafana/Uptime Kuma.
6. Test login and denial paths.
7. Document account recovery.

### Deliverables

- auth stack
- Authelia config template
- encrypted auth secrets
- auth runbook

### Done criteria

- Sensitive route requires auth.
- MFA works for admin.
- Failed access is logged.

---

## Phase 8: Monitoring stack

### Goal

Deploy metrics, dashboards, and alerts.

### Tasks

1. Deploy Prometheus.
2. Deploy Grafana.
3. Deploy Node Exporter.
4. Deploy cAdvisor.
5. Deploy Alertmanager.
6. Add Traefik metrics scrape.
7. Add dashboards.
8. Add baseline alert rules.
9. Test alert delivery.

### Deliverables

- monitoring stack
- Prometheus configs
- Grafana provisioning
- alert rules
- monitoring runbook

### Done criteria

- Host/container metrics visible.
- Alerts fire in test mode.
- Dashboards load.

---

## Phase 9: Logging stack

### Goal

Centralize logs with bounded retention.

### Tasks

1. Deploy Loki.
2. Deploy Promtail or Alloy.
3. Collect Docker logs.
4. Collect Traefik logs.
5. Collect system logs if appropriate.
6. Add log retention.
7. Create Grafana log dashboards.
8. Test searching incident logs.

### Deliverables

- logging stack
- Loki config
- collector config
- log dashboard
- logging runbook

### Done criteria

- Container logs searchable in Grafana.
- Traefik logs searchable.
- Retention is bounded.

---

## Phase 10: Backup and restore

### Goal

Automate encrypted backups and prove restores work.

### Tasks

1. Install/configure restic.
2. Create backup repository.
3. Encrypt backup credentials with SOPS.
4. Write backup script.
5. Write database dump hooks.
6. Write forget/prune script.
7. Write restore script.
8. Add systemd timer.
9. Add backup monitoring.
10. Perform restore test.

### Deliverables

- backup scripts
- systemd timer
- backup runbook
- restore runbook
- restore test log

### Done criteria

- Backup completes automatically.
- Backup failure alerts.
- Restore test succeeds.

---

## Phase 11: Security controls

### Goal

Add runtime hardening, scanning, and threat controls.

### Tasks

1. Add Compose security defaults.
2. Document exceptions.
3. Add Trivy scans.
4. Add Syft SBOM generation.
5. Deploy CrowdSec for Traefik logs.
6. Configure fail2ban if SSH logs warrant it.
7. Add permission validation.
8. Add security dashboard/alerts.

### Deliverables

- security configs
- scan workflows
- SBOM artifacts
- security runbook

### Done criteria

- Critical images scanned.
- Security defaults applied where compatible.
- Public ingress has rate/security protections.

---

## Phase 12: CI validation

### Goal

Validate repo changes before merge.

### Tasks

1. Add CI workflow.
2. Add YAML lint.
3. Add shellcheck.
4. Add Compose validation.
5. Add secret scanning.
6. Add Trivy config scan.
7. Add test stack startup if runner supports Docker.
8. Publish CI status.

### Deliverables

- CI workflow files
- CI scripts
- contribution guide

### Done criteria

- Pull request fails on invalid Compose/YAML/secrets.
- Main branch protected by CI.

---

## Phase 13: Manual deployment pipeline

### Goal

Create controlled production deployment with manual approval.

### Tasks

1. Write deploy script.
2. Write preflight checks.
3. Write release metadata generation.
4. Add manual approval workflow.
5. Add health checks.
6. Add traffic verification.
7. Add notifications.
8. Document deployment runbook.

### Deliverables

- deploy scripts
- CI deploy workflow
- release metadata format
- deployment runbook

### Done criteria

- Nothing deploys automatically to production.
- Manual approved deploy works.
- Health and traffic checks run after deploy.

---

## Phase 14: Rollback automation

### Goal

Restore previous known-good state on failed deploy.

### Tasks

1. Capture pre-deploy state.
2. Store previous image digests.
3. Snapshot config/secrets refs.
4. Add rollback script.
5. Integrate rollback into deploy failure path.
6. Test rollback with a deliberately bad deployment.
7. Document rollback runbook.

### Deliverables

- rollback script
- rollback tests
- rollback runbook

### Done criteria

- Failed stateless deployment automatically rolls back.
- Previous service health is verified.
- Admin is notified.

---

## Phase 15: DNS filtering and split DNS

### Goal

Add optional DNS filtering for tailnet and/or LAN.

### Tasks

1. Choose AdGuard Home or Pi-hole.
2. Deploy DNS stack.
3. Configure upstream resolvers.
4. Configure blocklists.
5. Configure Tailscale DNS/split DNS.
6. Test normal DNS and blocked domains.
7. Document failure/recovery.

### Deliverables

- DNS stack
- DNS docs
- Tailscale split DNS config notes

### Done criteria

- Tailnet clients resolve internal names.
- DNS filtering works.
- DNS outage recovery is documented.

---

## Phase 16: Advanced Tailscale modes

### Goal

Enable only the Tailscale modes actually needed.

### Tasks

1. Evaluate need for subnet router.
2. Enable subnet routes if needed.
3. Evaluate need for exit node.
4. Enable exit node only for trusted admins if needed.
5. Configure ACL restrictions.
6. Test MagicDNS, SSH, split DNS.
7. Document mode-specific operations.

### Deliverables

- updated Tailscale policy
- Tailscale modes runbook
- route test results

### Done criteria

- Enabled modes have clear justification.
- ACLs restrict route/exit usage.
- Emergency recovery workflow tested.

---

## Phase 17: Add first real application

### Goal

Deploy one production app using the platform standards.

### Tasks

1. Create service folder from template.
2. Define Compose service.
3. Attach only required networks.
4. Add Traefik labels.
5. Add health check.
6. Add secrets via SOPS.
7. Add backup rules.
8. Add monitoring/logging labels.
9. Add service README.
10. Deploy through manual pipeline.

### Deliverables

- app stack
- service docs
- monitoring/backup integration

### Done criteria

- App works publicly or privately as intended.
- Health checks and backups work.
- Rollback path exists.

---

## Phase 18: Documentation completion

### Goal

Make platform self-documenting.

### Tasks

1. Finish architecture docs.
2. Finish network docs.
3. Finish security docs.
4. Finish runbooks.
5. Add troubleshooting guides.
6. Add upgrade guides.
7. Add disaster recovery guide.
8. Review docs for accuracy against actual config.

### Deliverables

- complete docs tree
- diagrams
- runbooks

### Done criteria

- A new admin can understand and recover platform from docs.
- Docs match actual files.

---

## Phase 19: Multi-node preparation

### Goal

Prepare architecture for future nodes without redesign.

### Tasks

1. Add host inventory model.
2. Add naming/tagging conventions.
3. Add per-host Compose profiles.
4. Add backup target abstraction.
5. Add second Tailscale node plan.
6. Add second tunnel connector plan.
7. Document migration paths to Nomad/k3s.

### Deliverables

- multi-node docs
- host inventory template
- scaling ADR

### Done criteria

- Adding a NUC/NAS requires adding inventory and stack assignment, not redesign.

---

## Phase 20: Quarterly operational review

### Goal

Keep platform healthy over time.

### Tasks

1. Review backups and restore tests.
2. Review alerts/noise.
3. Review security updates.
4. Review image vulnerability reports.
5. Review Tailscale ACLs.
6. Review exposed routes.
7. Review disk capacity.
8. Update documentation.

### Deliverables

- quarterly review report
- action items
- updated risks

### Done criteria

- Platform remains secure, documented, and recoverable.

---

---

# 27. Small-Model Session Prompts

Use these prompts one session at a time with a smaller model such as DeepSeek V4 Flash. Each session is intentionally scoped. Tell the model to modify files directly if it has tools, or output only the requested files if not.

## Global instruction to prepend to every small-model session

```text
You are implementing a production-grade homelab platform repository. Use free and open-source software wherever possible. Optimize for stability, security, maintainability, observability, and reliability. Do not expose router ports directly. Public access must be Cloudflare DNS -> Cloudflare Tunnel -> Traefik -> services. Private administration must use Tailscale. Keep changes modular, documented, and GitOps-inspired. Do not commit plaintext secrets. Use placeholders and SOPS-encrypted file templates for secrets.

Mandatory session behavior:
- Start every session with a question gate. Ask any clarifying questions needed to avoid guessing, especially for accounts, domains, tokens, API keys, credentials, DNS zones, Cloudflare Tunnel details, Tailscale settings, Git/CI access, SMTP/notification settings, backup repository credentials, and proxy requirements.
- Never paste, hardcode, commit, or print real secrets. If a real token/key/password is required, stop and ask the user to provide it through a secure local mechanism such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate proxy, LAN proxy, or reverse-proxy/domain settings are required before writing network-dependent configuration.
- Verify each major step with commands, file reads, linters, config validation, tests, or explicit inspection before continuing.
- Do not mark a session complete until every Done criterion is verified with evidence.
- Do not start or recommend the next session until the user gives an explicit green signal.
```

---

## Session 1 Prompt: Create repository skeleton

```text
Task: Create the initial homelab-platform repository skeleton.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create the directory tree for docs, infra, compose, stacks, configs, secrets, scripts, ci, templates, tests, releases.
2. Create README.md explaining the platform goals:
   - free software where possible
   - production-grade homelab
   - single PiKVM V4 today
   - expandable to more nodes later
   - public ingress through Cloudflare Tunnel and Traefik only
   - private admin through Tailscale
3. Create .gitignore that excludes decrypted secrets, runtime env files, logs, local backups, and generated artifacts.
4. Create .editorconfig.
5. Create docs/decisions/ADR-0001-platform-principles.md.
6. Do not create real secrets.

Deliverables:
- Complete folder structure.
- README.md.
- .gitignore.
- .editorconfig.
- ADR-0001.

Done criteria:
- Repo structure exists.
- No plaintext secret files exist.
- README is clear enough for a new admin.
```

---

## Session 2 Prompt: Host bootstrap and Docker baseline

```text
Task: Add host bootstrap files for a PiKVM V4 or laptop Docker host.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create infra/host/docker/daemon.json with Docker json-file log rotation.
2. Create scripts/bootstrap/00-check-host.sh to verify Linux, Docker availability, CPU arch, disk space, memory, and required commands.
3. Create scripts/bootstrap/01-install-docker.sh as a documented script skeleton with safe checks and comments.
4. Create scripts/bootstrap/04-setup-firewall.sh as a documented deny-by-default firewall skeleton using ufw or nftables, with Tailscale allowance notes.
5. Create docs/runbooks/host-bootstrap.md explaining how to prepare the host.
6. Do not make destructive assumptions.

Deliverables:
- Docker daemon config.
- Bootstrap scripts.
- Host bootstrap runbook.

Done criteria:
- Scripts are idempotent or clearly documented.
- Docker logs are bounded.
- Firewall plan blocks inbound by default and permits Tailscale/admin access.
```

---

## Session 3 Prompt: Tailscale baseline design files

```text
Task: Add Tailscale baseline configuration and documentation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create infra/tailscale/README.md.
2. Create infra/tailscale/policy.hujson example with groups, tags, ACLs, and SSH policy placeholders.
3. Include tags: tag:prod, tag:server, tag:pikvm, tag:monitoring, tag:ci, tag:backup, tag:exit-node, tag:subnet-router.
4. Document MagicDNS, Tailscale SSH, normal node, subnet router, exit node, split DNS, and emergency recovery.
5. Create docs/runbooks/tailscale-recovery.md.
6. Make clear that normal node + MagicDNS is day-one; exit node/subnet router are optional and ACL-restricted.

Deliverables:
- Tailscale policy example.
- Tailscale docs.
- Recovery runbook.

Done criteria:
- Policy is least-privilege oriented.
- Admin access is documented.
- Optional modes are not enabled blindly.
```

---

## Session 4 Prompt: Docker networks and Compose foundation

```text
Task: Create Docker network and Compose foundation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create compose/networks.yml defining proxy, public, private, management, monitoring, database, shared, backup, security networks.
2. Mark sensitive networks internal where appropriate.
3. Create scripts/bootstrap/02-create-networks.sh to create external networks idempotently.
4. Create docs/architecture/network.md explaining every network, which containers belong where, and forbidden communication paths.
5. Create templates/service/compose.yml.template for a new service with security defaults, healthcheck placeholder, and Traefik labels disabled by default.

Deliverables:
- compose/networks.yml.
- network creation script.
- network architecture docs.
- service template.

Done criteria:
- Network names match platform standard.
- Database and management networks are not exposed by default.
- Template does not expose services accidentally.
```

---

## Session 5 Prompt: Traefik proxy stack

```text
Task: Create the Traefik reverse proxy stack.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/proxy/compose.yml with Traefik service attached to proxy and monitoring networks.
2. Configure Docker provider with exposedByDefault=false.
3. Create stacks/proxy/traefik/static.yml.
4. Create dynamic config files for middlewares, security headers, TLS options, and rate limits.
5. Add protected dashboard pattern; dashboard must not be anonymously public.
6. Enable ping and metrics internally.
7. Create docs/architecture/traefik.md and docs/runbooks/traefik.md.
8. Use placeholders for domain names and secrets.

Deliverables:
- Proxy Compose stack.
- Traefik static/dynamic configs.
- Documentation and runbook.

Done criteria:
- Traefik discovery is explicit only.
- Dashboard is protected/private.
- Middleware chain includes security headers and rate limit.
```

---

## Session 6 Prompt: Cloudflare Tunnel stack

```text
Task: Add Cloudflare Tunnel stack and documentation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Add cloudflared service to stacks/proxy/compose.yml or a separate stacks/proxy/cloudflared compose fragment.
2. Create stacks/proxy/cloudflared/config.yml.template.
3. Route example hostnames to Traefik.
4. Include safe default final rule returning 404.
5. Create infra/cloudflare/README.md explaining DNS records, tunnel setup, token handling, and recovery.
6. Create scripts/validate/validate-cloudflared.sh to parse/check config presence.
7. Do not include real tunnel credentials.

Deliverables:
- cloudflared config template.
- docs for Cloudflare DNS/Tunnel.
- validation script.

Done criteria:
- Public ingress path is Cloudflare Tunnel -> Traefik.
- No direct port exposure is suggested.
- Credentials are referenced as secrets only.
```

---

## Session 7 Prompt: SOPS + age secrets framework

```text
Task: Add SOPS + age secret management framework.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create .sops.yaml with placeholder age recipient.
2. Create secrets/README.md explaining no plaintext secrets, key custody, decryption flow, and rotation.
3. Create sample encrypted-file templates using placeholder values but do not fake real encrypted blobs unless SOPS is actually run.
4. Create scripts/validate/validate-secrets.sh to check for plaintext secret anti-patterns and required files.
5. Create scripts/deploy/render-secrets.sh skeleton that decrypts SOPS files into runtime env files with 0600 permissions.
6. Create docs/runbooks/secrets.md.

Deliverables:
- .sops.yaml.
- secrets docs.
- validation/render scripts.
- runbook.

Done criteria:
- No real secret values are committed.
- Workflow is clear and secure.
- Runtime secret files are generated, not manually edited.
```

---

## Session 8 Prompt: Authelia authentication stack

```text
Task: Add Authelia authentication stack for Traefik ForwardAuth.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/auth/compose.yml for Authelia with minimal dependencies.
2. Create Authelia configuration template with placeholders.
3. Add Traefik dynamic middleware for forward-auth integration.
4. Store secrets as SOPS placeholders only.
5. Create docs/architecture/authentication.md and docs/runbooks/authentication.md.
6. Include MFA requirement for admin services.
7. Document account recovery and lockout procedure.

Deliverables:
- Auth stack.
- Config templates.
- Traefik middleware update.
- Auth docs/runbook.

Done criteria:
- Admin dashboards can be protected by forward-auth.
- No plaintext auth secrets.
- MFA and recovery are documented.
```

---

## Session 9 Prompt: Monitoring stack

```text
Task: Add Prometheus/Grafana/Alertmanager monitoring stack.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/monitoring/compose.yml with Prometheus, Grafana OSS, Alertmanager, Node Exporter, cAdvisor, Blackbox Exporter, and Uptime Kuma if appropriate.
2. Create Prometheus scrape config for host, cAdvisor, Traefik, and blackbox checks.
3. Create baseline alert rules for disk, host down, container down, Traefik 5xx, backup stale, certificate expiry.
4. Create Grafana provisioning for datasource and dashboard folder placeholders.
5. Create docs/architecture/monitoring.md and docs/runbooks/monitoring.md.

Deliverables:
- Monitoring Compose stack.
- Prometheus config and rules.
- Grafana provisioning.
- Docs/runbook.

Done criteria:
- Metrics stack is modular.
- Critical alerts are defined.
- Dashboards can be provisioned as code.
```

---

## Session 10 Prompt: Logging stack

```text
Task: Add centralized logging stack.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/logging/compose.yml with Loki and Promtail or Grafana Alloy.
2. Configure collection of Docker container logs and Traefik logs.
3. Add Loki retention settings suitable for small disk.
4. Create Grafana datasource provisioning update if needed.
5. Create docs/architecture/logging.md and docs/runbooks/logging.md.
6. Document Docker daemon log rotation and sensitive log handling.

Deliverables:
- Logging stack.
- Collector config.
- Loki config.
- Docs/runbook.

Done criteria:
- Logs are centralized and searchable.
- Retention is bounded.
- Sensitive data handling is documented.
```

---

## Session 11 Prompt: Backup and restore framework

```text
Task: Add restic-based backup and restore framework.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/backups or scripts/backup with backup.sh, restore.sh, check.sh, forget-prune.sh, restore-test.sh.
2. Include backup of Compose repo, configs, SOPS-encrypted secrets, Docker volumes, database dumps, ACME/certs, selected logs.
3. Use restic with encrypted repository and SOPS-managed credentials.
4. Add systemd service/timer examples.
5. Add Uptime Kuma push monitor or notification hook placeholder.
6. Create docs/architecture/backups.md, docs/runbooks/backup.md, docs/runbooks/restore.md.
7. Include retention policy and restore-test procedure.

Deliverables:
- Backup scripts.
- Systemd timer examples.
- Backup/restore docs.

Done criteria:
- Backups are encrypted.
- Restore testing is documented and scripted.
- Backup failure can alert.
```

---

## Session 12 Prompt: Security scanning and hardening

```text
Task: Add security scanning and hardening framework.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create scripts/validate/validate-permissions.sh for secret files, acme.json, age keys, scripts.
2. Create scripts/validate/validate-compose-security.sh checking for risky Compose patterns: privileged containers, raw Docker socket mounts, missing restart policies, host networking, missing no-new-privileges where expected.
3. Add ci/scripts/ci-scan.sh using Trivy and Syft if available.
4. Create infra/security/README.md documenting least privilege, container hardening, CrowdSec, fail2ban, firewall, update policy.
5. Add docs/architecture/security.md.

Deliverables:
- Security validation scripts.
- Scan script.
- Security docs.

Done criteria:
- Risky Compose patterns are detectable.
- Image scanning and SBOM generation are planned.
- Security exceptions must be documented.
```

---

## Session 13 Prompt: CI validation workflows

```text
Task: Add free CI validation workflows.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create ci/github-actions/validate.yml for YAML lint, shellcheck, compose config, secret scan, Trivy config scan.
2. Create ci/woodpecker/.woodpecker.yml equivalent or documented skeleton.
3. Create ci/README.md comparing GitHub Actions, Forgejo Actions, Gitea Actions, Woodpecker CI, Drone CE.
4. Ensure CI only validates by default and does not deploy production automatically.
5. Add manual workflow dispatch skeleton for release/deploy with explicit approval notes.

Deliverables:
- CI workflow files.
- CI README.
- Manual deploy skeleton.

Done criteria:
- Pull requests can be validated.
- Production deploy requires manual approval.
- Free/FOSS path is documented.
```

---

## Session 14 Prompt: Deployment scripts and release metadata

```text
Task: Add manual deployment pipeline scripts.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create scripts/deploy/preflight.sh.
2. Create scripts/deploy/deploy.sh.
3. Create scripts/deploy/healthcheck.sh.
4. Create scripts/deploy/verify-traffic.sh.
5. Create release metadata format under releases/README.md.
6. Deployment must capture current Git SHA, image digests, rendered Compose config, and timestamp before changes.
7. Deployment must require explicit confirmation or approved CI environment.
8. Create docs/runbooks/deploy.md.

Deliverables:
- Deploy scripts.
- Release metadata docs.
- Deployment runbook.

Done criteria:
- Deploy is not automatic.
- Preflight checks run before changes.
- Health and traffic verification run after changes.
```

---

## Session 15 Prompt: Rollback automation

```text
Task: Add rollback automation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create scripts/deploy/rollback.sh.
2. Rollback should restore previous Git SHA or release artifact, previous Compose config, previous image digests, previous config snapshot, and previous secrets references.
3. Include database restore hook but require explicit manual confirmation for destructive DB restores.
4. Integrate rollback call into deploy failure path as a documented option.
5. Create docs/runbooks/rollback.md.
6. Add tests or a dry-run mode.

Deliverables:
- rollback.sh.
- rollback runbook.
- dry-run/test mode.

Done criteria:
- Stateless service rollback is automatic-capable.
- Stateful rollback is conservative.
- Health verification runs after rollback.
```

---

## Session 16 Prompt: DNS filtering and split DNS

```text
Task: Add optional DNS filtering stack design.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/dns/compose.yml with profiles for AdGuard Home and Pi-hole, but document choosing one primary.
2. Add Unbound optional profile.
3. Create docs/architecture/dns.md explaining LAN DNS, Tailscale DNS, split DNS, upstreams, and failure handling.
4. Create docs/runbooks/dns.md.
5. Include Tailscale DNS integration notes.
6. Do not force DNS stack into production by default.

Deliverables:
- DNS stack with profiles.
- DNS architecture docs.
- DNS runbook.

Done criteria:
- AdGuard/Pi-hole choice is explicit.
- Split DNS is documented.
- DNS outage recovery is documented.
```

---

## Session 17 Prompt: First application template implementation

```text
Task: Add an example public and private application stack using the platform standards.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/apps/example-public-app/compose.yml with a harmless demo container such as whoami or nginx unprivileged.
2. Add Traefik labels for public route with placeholder domain.
3. Add security defaults and health check.
4. Create stacks/apps/example-private-app/compose.yml with no public exposure by default.
5. Create README.md for each app documenting networks, exposure, backup, health, rollback.
6. Add tests validating that only the public app attaches to proxy.

Deliverables:
- Example public app.
- Example private app.
- Service docs.
- Network exposure test.

Done criteria:
- Public exposure is explicit.
- Private app is not routed by Traefik.
- Templates teach future service pattern.
```

---

## Session 18 Prompt: Disaster recovery documentation

```text
Task: Create full disaster recovery documentation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create docs/architecture/disaster-recovery.md.
2. Include recovery scenarios: bad deploy, broken Traefik, tunnel failure, host disk failure, lost age key, DB corruption, compromised service, hardware failure.
3. Define RTO/RPO by service class.
4. Include full host rebuild procedure.
5. Include emergency kit checklist.
6. Include quarterly restore drill procedure.

Deliverables:
- Disaster recovery doc.
- Restore drill checklist.

Done criteria:
- A new admin can rebuild on a laptop/NUC from backups.
- Emergency access via Tailscale/local console is documented.
```

---

## Session 19 Prompt: Multi-node scaling documentation

```text
Task: Add future expansion and multi-node scaling docs.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create docs/architecture/scaling-roadmap.md.
2. Cover adding NAS, Raspberry Pi, NUC, mini PC, VPS.
3. Cover multiple Cloudflare tunnel connectors.
4. Cover multiple Tailscale subnet routers and exit nodes.
5. Cover multi-host Docker Compose, Ansible, Docker Swarm, Nomad, and Kubernetes/k3s migration paths.
6. Cover distributed storage options and warnings.
7. Create host inventory template.

Deliverables:
- Scaling roadmap.
- Host inventory template.

Done criteria:
- Future nodes can be added without redesign.
- Kubernetes/Nomad are migration paths, not day-one requirements.
```

---

## Session 20 Prompt: Final documentation review and consistency pass

```text
Task: Perform a final consistency review of the homelab-platform repository.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Check that all docs agree on network names.
2. Check that public ingress is always Cloudflare Tunnel -> Traefik.
3. Check that no docs recommend direct inbound router port forwards.
4. Check that secrets are always SOPS/age or placeholders.
5. Check that production deploy always requires manual approval.
6. Check that backup/restore/rollback docs are linked from README.md.
7. Check that every stack has a README.md.
8. Create docs/troubleshooting/common-failures.md if missing.
9. Produce a summary of inconsistencies fixed.

Deliverables:
- Consistency fixes.
- Common troubleshooting doc.
- Final review summary.

Done criteria:
- Documentation is coherent and self-documenting.
- Major runbooks are easy to find.
- Platform principles are consistently enforced.
```

---

---

# 29. Final Recommended Architecture

## 29.1 Final architecture summary

Start with:

- PiKVM V4 as a single production Docker Compose host.
- Cloudflare DNS + Cloudflare Tunnel for all public ingress.
- Traefik as the only internal reverse proxy and routing point.
- Tailscale as private admin plane with MagicDNS, ACLs, tags, and SSH.
- SOPS + age for GitOps-compatible secrets.
- Prometheus/Grafana/Alertmanager/Uptime Kuma for monitoring and alerting.
- Loki + Promtail/Alloy for centralized logs.
- restic for encrypted backups and restore tests.
- CI validation with GitHub Actions and a separately hosted local M3 Mac self-hosted runner initially; laptop deployment target only after explicit retarget approval.
- Manual approval required before production deployment.

## 29.2 Major decision justifications

| Decision | Justification |
|---|---|
| Docker Compose first | Stable, simple enough for one node, portable, easy to validate, no Kubernetes overhead |
| Traefik | Docker-native discovery, middleware, metrics, ACME, easy migration path |
| Cloudflare Tunnel | Required public access model, no inbound ports, hides home IP |
| Tailscale | Secure private admin, ACLs, MagicDNS, SSH, subnet/exit flexibility |
| SOPS + age | Lightweight FOSS secret workflow, GitOps-friendly, avoids heavy Vault day one |
| Authelia | Lightweight self-hosted auth and MFA for admin apps |
| Prometheus/Grafana | Standard OSS monitoring stack, portable to future platforms |
| Loki | Lightweight central logging integrated with Grafana |
| restic | Encrypted, deduplicated, backend-flexible backups with simple restore |
| Manual deploy approval | Prevents accidental production changes and aligns with production-grade operations |
| Multiple Docker networks | Enforces trust boundaries and limits lateral movement |
| CI validation before deploy | Finds YAML/Compose/secrets/security issues early |
| Rollback snapshots | Ensures failed deploys can recover quickly |

## 29.3 When to enable optional features

| Feature | Enable when |
|---|---|
| Tailscale subnet router | Remote access to LAN devices is needed |
| Tailscale exit node | You need trusted internet egress while traveling |
| Exit node + DNS filtering | Remote clients need consistent filtered DNS |
| AdGuard Home/Pi-hole | You want DNS filtering or split DNS beyond MagicDNS |
| Tailscale Serve | Temporary/private tailnet-only exposure is useful |
| Tailscale Funnel | Emergency/temporary public exposure; not default production path |
| CrowdSec | Once public apps receive real traffic |
| Forgejo/Woodpecker | When avoiding SaaS becomes more important than setup simplicity |
| Nomad/k3s | When multiple nodes and scheduling needs justify complexity |
| Distributed storage | Only after storage requirements exceed simple NAS/local volumes |

## 29.4 Final target diagram

```text
                                   +-----------------------+
                                   | GitOps Source of Truth|
                                   | repo + docs + secrets |
                                   +-----------+-----------+
                                               |
                                               v
                                   +-----------------------+
                                   | CI Validation          |
                                   | lint/test/scan/SBOM    |
                                   +-----------+-----------+
                                               | manual approval
                                               v
Internet --> Cloudflare DNS/Edge --> Cloudflare Tunnel --> Traefik
                                                                 |
          Tailscale private admin plane -------------------------+
                                                                 |
                              +----------------------------------+----------------------------------+
                              v                                  v                                  v
                       Public Apps                         Auth/Security                       Observability
                    proxy/public/db                     Authelia/CrowdSec                  Prom/Grafana/Loki
                              |                                  |                                  |
                              +----------------------------------+----------------------------------+
                                                                 v
                                                          Backups/restic
                                                                 |
                                                                 v
                                                        USB/NAS/SFTP/offline
```

---

---

## End State

When all phases are complete, the homelab will operate as a small but production-grade cloud platform:

- Public services enter only through Cloudflare Tunnel and Traefik.
- Private administration uses Tailscale with ACLs and MagicDNS.
- Services are isolated by Docker networks.
- Secrets are encrypted in Git with SOPS + age.
- CI validates configuration, secrets, images, and security before deployment.
- Production deployment requires explicit manual approval.
- Monitoring, logging, backups, restore tests, and rollback are first-class platform features.
- The structure is ready to scale from one PiKVM V4 to multiple Docker hosts, NAS, NUC, VPS, Nomad, or Kubernetes without redesigning the foundations.
