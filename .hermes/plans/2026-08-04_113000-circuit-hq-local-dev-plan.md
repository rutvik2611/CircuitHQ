# CircuitHQ — Homelab Platform Local Development Plan

> **For Hermes:** Phase-by-phase implementation plan. Build locally on M3 Mac first, validate with GitHub Actions CI (using M3 Mac self-hosted runner), and only retarget to the laptop deployment target after explicit user approval.

**Goal:** Implement the complete homelab platform blueprint as an organized Git repository, starting with local development on the M3 Mac, with CI validation via GitHub Actions, and a clear path to eventual deployment on an M3 backend target.

**Architecture:** A single-node Docker Compose homelab with Cloudflare Tunnel → Traefik ingress, Tailscale private admin, SOPS+age secrets, Prometheus/Grafana/Loki observability, restic backups, and GitOps-style delivery — all built and validated locally before any target deployment.

**Tech Stack:** Docker CE + Compose, Traefik, Cloudflare Tunnel, Tailscale, SOPS + age, Prometheus/Grafana/Loki, restic, Authelia, Trivy, Syft, GitHub Actions (self-hosted M3 Mac runner), Make

**M3 "Backend" Context:** The M3 Mac is both the daily driver for LOCAL development/validation AND the eventual deployment target (laptop). CI runs on a self-hosted M3 Mac runner. The deploy target is the same machine. This means: (a) ARM64 compatibility is always assured, (b) no cross-arch complexity, (c) but also no separation — so staging/production isolation must be via Compose projects, not machines.

---

## Phase 0: Project Structure & Repo Bootstrap

**Objective:** Lay down the full directory skeleton, gitignore, editorconfig, Makefile, and ADR-0001.

### Files to Create

- `README.md` — platform goals, reading order, quickstart
- `CHANGELOG.md` — empty template
- `LICENSE` — MIT
- `.gitignore` — exclude decrypted secrets, runtime env files, logs, local backups, artifacts
- `.editorconfig` — YAML/MD/shell/Compose standards
- `.sops.yaml` — placeholder SOPS config
- `Makefile` — `make validate`, `make lint`, `make compose-config`, `make secrets-check`, `make security-scan`, `make integration-test`, `make evidence`
- `docs/decisions/ADR-0001-platform-principles.md` — capture blueprint's non-negotiable goals
- `docs/` — architecture/, runbooks/, decisions/, diagrams/, troubleshooting/ stubs
- `infra/` — host/, tailscale/, cloudflare/, security/ stubs
- `compose/` — networks.yml, volumes.yml, profiles/ stubs
- `stacks/` — proxy/, auth/, monitoring/, logging/, backups/, dns/, apps/ stubs
- `configs/` — common/, production/, staging/, templates/
- `secrets/` — production/, staging/ + README.md
- `scripts/` — bootstrap/, deploy/, backup/, validate/, maintenance/
- `ci/` — github-actions/, forgejo-actions/, woodpecker/
- `templates/` — service/, traefik/, docs/
- `tests/` — compose/, traefik/, cloudflare/, networking/, backups/, security/
- `releases/` — .gitkeep

### Validation

```bash
make validate  # placeholder — exists and runs
git status      # no decrypted secrets, no .env files
docker compose -f compose/networks.yml config  # once networks.yml exists
```

---

## Phase 1: Host Bootstrap & Docker Baseline

**Objective:** Scripts and configs to prepare any macOS host (M3 Mac) as a Docker homelab node.

### Files to Create/Modify

- `infra/host/docker/daemon.json` — log rotation (max-size 10m, max-file 3), no raw socket exposure
- `scripts/bootstrap/00-check-host.sh` — verify Docker, Compose, OS, arch (ARM64 expected), disk space
- `scripts/bootstrap/01-install-docker.sh` — documented Docker Desktop/OrbStack/Colima install steps (macOS comments)
- `scripts/bootstrap/02-create-networks.sh` — create Docker networks: proxy, public, private, management, monitoring, database, shared, backup, security
- `scripts/bootstrap/04-setup-firewall.sh` — macOS built-in firewall notes (no nftables on macOS — document instead)
- `docs/runbooks/host-bootstrap.md` — complete host prep runbook

### Docker Networks Design

| Network | Internal | Purpose |
|---------|----------|---------|
| `proxy` | no | Traefik ↔ cloudflared, Traefik ↔ public services |
| `public` | no | Public apps that need Traefik routes |
| `private` | yes | Private/admin-only services |
| `management` | yes | Portainer/management dashboards |
| `monitoring` | yes | Prometheus → exporters/Grafana |
| `database` | yes | DB containers only |
| `shared` | no | Shared service-to-service comms |
| `backup` | yes | Backup container → volume access |
| `security` | yes | CrowdSec, fail2ban |

### Validation

```bash
make bootstrap-check  # scripts/bootstrap/00-check-host.sh
docker network ls     # verify all networks exist after phase
make compose-config   # verify compose/networks.yml renders
```

---

## Phase 2: Tailscale Baseline Design Files

**Objective:** Tailscale config-as-code and docs — NOT actual Tailscale installation on the cluster yet (that's for target deployment). This phase just creates the repo artifacts.

### Files to Create

- `infra/tailscale/README.md`
- `infra/tailscale/policy.hujson` — groups, tags (tag:prod, tag:server, tag:pikvm, tag:monitoring, tag:ci, tag:backup, tag:exit-node, tag:subnet-router), ACLs, SSH policy placeholders
- `docs/architecture/tailscale.md` — MagicDNS, normal node, exit node, subnet router modes
- `docs/runbooks/tailscale-recovery.md`

### Design Decisions

- Normal node + MagicDNS is day-one baseline
- Exit node and subnet router are optional, ACL-restricted, not enabled by default
- ACLs are least-privilege: admin group gets SSH + private dashboards, CI group gets restricted

### Validation

```bash
make lint                         # yamllint on .hujson, shellcheck
make evidence                     # verify all 4 files exist
```

---

## Phase 3: Docker Networks & Compose Foundation

**Objective:** Working Compose foundation with network definitions, volume definitions, and service templates.

### Files to Create/Modify

- `compose/networks.yml` — all 9 Docker networks (declared as external)
- `compose/volumes.yml` — shared volume declarations (prometheus, grafana, loki, traefik-acme, etc.)
- `scripts/validate/validate-networks.sh` — verify correct network existence
- `docs/architecture/network.md` — network diagram, forbidden communication paths, container-network mapping
- `templates/service/compose.yml.template` — new service with:
  - `no-new-privileges: true`
  - `cap_drop: [ALL]`
  - `read_only: true` with `tmpfs: [/tmp]`
  - `restart: unless-stopped`
  - healthcheck placeholder
  - Traefik labels disabled by default
  - explicit network attachment (never `proxy` unless public)

### Compose Project Convention

- All services use `project_name: circuithq` (configurable per env)
- `profiles/` for selective startup (public, monitoring, backups, media, devtools)
- `compose/production.yml` as top-level entrypoint that includes all profile files

### Validation

```bash
make compose-config       # docker compose -f compose/networks.yml config
make validate-networks    # scripts/validate/validate-networks.sh
make lint                 # yamllint
```

---

## Phase 4: Traefik Reverse Proxy

**Objective:** Deploy Traefik locally on the M3 Mac as the internal ingress controller.

### Files to Create

- `stacks/proxy/compose.yml` — Traefik service, networks: `proxy`, `monitoring`
- `stacks/proxy/traefik/static.yml` — entrypoints (web 80, websecure 443), providers (Docker, file), ping, metrics
- `stacks/proxy/traefik/dynamic/middlewares.yml` — security headers, rate limit, auth middleware placeholders
- `stacks/proxy/traefik/dynamic/tls.yml` — TLS options, ACME placeholder config
- `stacks/proxy/traefik/dynamic/security-headers.yml`
- `stacks/proxy/traefik/dynamic/rate-limits.yml`
- `docs/architecture/traefik.md`
- `docs/runbooks/traefik.md`

### Key Config Rules

- `providers.docker.exposedByDefault: false` — explicit labels required
- Dashboard route: `api@internal` on internal router, protected
- Metrics endpoint on `monitoring` network only
- ACME: let's encrypt staging initially, production later
- Middleware chain: rate-limit → security-headers → auth → service

### Validation

```bash
make integration-test      # start proxy stack, verify health
docker compose -f stacks/proxy/compose.yml up -d
curl -f http://localhost:8080/api/rawstatus  # Traefik ping
make compose-config        # full compose render
```

---

## Phase 5: Cloudflare Tunnel Stack (Config Only)

**Objective:** Create cloudflared config templates and docs. Actual tunnel creation requires Cloudflare account interaction and is done during deployment, not pure repo work. On M3 Mac locally, we validate config syntax only — we don't run the tunnel.

### Files to Create

- `stacks/proxy/cloudflared/config.yml.template` — ingress rules placeholder
- `infra/cloudflare/README.md` — DNS records, tunnel setup steps, token handling
- `scripts/validate/validate-cloudflared.sh` — YAML parse, ingress route sanity
- `docs/runbooks/tunnel-outage.md` — recovery procedures

### Config Template Shape

```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: "*.circuithq.example.com"
    service: http://traefik:80
  - hostname: "circuithq.example.com"
    service: http://traefik:80
  - service: http_status:404
```

### Validation

```bash
make lint                           # yamllint on template
scripts/validate/validate-cloudflared.sh  # parse check
make compose-config                 # verify it includes in render
```

---

## Phase 6: SOPS + Age Secrets Framework

**Objective:** Secrets-as-code framework without real secrets. Create the structure, scripts, and documentation.

### Files to Create

- `.sops.yaml` — creation rules: `secrets/production/*.sops.yaml` → age, `secrets/staging/*.sops.yaml` → age
- `secrets/README.md` — key custody, decryption flow, rotation, no plaintext policy
- `scripts/deploy/render-secrets.sh` — decrypt SOPS files → `.env` with 0600 perms
- `scripts/validate/validate-secrets.sh` — gitleaks, no `.env.production`, no decrypted SOPS, `.env.example` pattern
- `docs/runbooks/secrets.md`

### SOPS File Templates (Placeholder Values Only)

- `secrets/production/cloudflare.sops.yaml`
- `secrets/production/traefik.sops.yaml`
- `secrets/production/authelia.sops.yaml`
- `secrets/production/grafana.sops.yaml`
- `secrets/production/restic.sops.yaml`
- `secrets/staging/example.sops.yaml`

### Age Key Strategy

- Generate age key locally on M3 Mac before deployment
- Store key at `~/.config/sops/age/keys.txt` (0600)
- Back up key offline
- Separate keys for production and staging
- `.sops.yaml` references the public key, never the private key

### Validation

```bash
make secrets-check          # gitleaks + validate-secrets.sh
git secrets --scan          # no real secrets in working tree
```

---

## Phase 7: Authelia Authentication Stack

**Objective:** ForwardAuth layer for protecting admin/sensitive routes.

### Files to Create

- `stacks/auth/compose.yml` — Authelia + Redis for session store
- `stacks/auth/authelia/configuration.yml.template` — placeholders for users, secrets, domain, SMTP
- `stacks/proxy/traefik/dynamic/auth-middleware.yml` — forward auth middleware referencing Authelia
- `docs/architecture/authentication.md`
- `docs/runbooks/authentication.md`

### Auth Integration

- Traefik dashboard requires Authelia forward-auth
- Grafana, Uptime Kuma, Portainer behind auth
- MFA (TOTP) for admin user
- Session store via Redis
- Failed login logging

### Validation

```bash
make integration-test        # start auth stack, verify forward-auth chain
docker compose -f stacks/auth/compose.yml up -d
curl -f http://localhost:9091/api/verify  # Authelia health
```

---

## Phase 8: Monitoring Stack

**Objective:** Deploy Prometheus + Grafana + Node Exporter + cAdvisor + Alertmanager locally.

### Files to Create

- `stacks/monitoring/compose.yml` — prometheus, grafana, node-exporter, cadvisor, alertmanager
- `stacks/monitoring/prometheus/prometheus.yml` — scrape configs
- `stacks/monitoring/prometheus/rules/` — node, docker, traefik, backup alerts
- `stacks/monitoring/grafana/provisioning/datasources/prometheus.yml`
- `stacks/monitoring/grafana/provisioning/dashboards/` — host overview, docker overview, traefik, backup
- `stacks/monitoring/alertmanager/alertmanager.yml.template`
- `docs/architecture/monitoring.md`
- `docs/runbooks/monitoring.md`

### Metrics Targets

| Target | Port | Purpose |
|--------|------|---------|
| Node Exporter | 9100 | Host CPU/RAM/disk/network |
| cAdvisor | 8080 | Container CPU/RAM/restarts |
| Traefik | 8082 | Router/service metrics |
| Alertmanager | 9093 | Alert routing |
| Prometheus | 9090 | Self-scrape |

### Alert Rules (Baseline)

- Host down, disk > 80%/90%, memory pressure
- Container restart loop, container unhealthy
- Backup age > 26h, certificate < 21d
- Traefik high 5xx rate

### Validation

```bash
make integration-test        # start monitoring stack
curl -f http://localhost:9090/-/ready         # Prometheus
curl -f http://localhost:3000/api/health      # Grafana
```

---

## Phase 9: Logging Stack

**Objective:** Loki + Promtail for centralized container logging.

### Files to Create

- `stacks/logging/compose.yml` — loki, promtail
- `stacks/logging/loki/loki.yml` — retention 7-14 days, local storage
- `stacks/logging/promtail/promtail.yml` — Docker log scraping with labels
- `stacks/logging/grafana/provisioning/datasources/loki.yml`
- `docs/architecture/logging.md`
- `docs/runbooks/logging.md`

### Retention

- Loki: 14 days local (adjustable per disk)
- Docker json-file: 3 × 10MB per container

### Validation

```bash
make integration-test
curl -f http://localhost:3100/ready                    # Loki
curl -f 'http://localhost:3100/loki/api/v1/labels'    # Labels visible
```

---

## Phase 10: Backup & Restore Framework

**Objective:** Scripts, configs, and documentation for restic-based backups. Actual backup repository setup happens during deployment.

### Files to Create

- `stacks/backups/compose.yml` — restic container (optional, or run host-level)
- `scripts/backup/backup.sh` — restic backup with pre/post hooks
- `scripts/backup/restore.sh` — restic restore
- `scripts/backup/restore-test.sh` — automated restore verification
- `scripts/backup/forget-prune.sh` — retention policy enforcement
- `infra/host/systemd/backup.service` + `backup.timer` — systemd timer for scheduled backups
- `docs/architecture/backups.md`
- `docs/runbooks/restore.md`
- `docs/runbooks/backup.md`

### Backup Scope

| Data | Method | Frequency |
|------|--------|-----------|
| Git repo + configs | restic | Daily + pre-deploy |
| Docker volumes | restic | Daily |
| Databases (pg_dump/mysqldump) | logical dump + restic | Daily + pre-deploy |
| SOPS-encrypted secrets | Git + restic | On change + daily |
| Traefik ACME certs | restic | Daily + on renew |

### Retention

- Hourly: 24, Daily: 14, Weekly: 8, Monthly: 12, Yearly: 3

### Validation

```bash
make backup-check            # scripts/validate/validate-backup.sh
shellcheck scripts/backup/*.sh
```

---

## Phase 11: Security Controls

**Objective:** Compose security defaults, image scanning, SBOM, and runtime hardening docs.

### Files to Create

- `infra/security/README.md` — security hardening overview
- `infra/security/hardening-checklist.md` — per-service checklist
- `scripts/ci/ci-scan.sh` — Trivy filesystem + config scan + Syft SBOM
- `scripts/validate/validate-permissions.sh` — file permission checks
- `.github/workflows/04-security-scan.yml` — CI security scan (detailed below in CI section)

### Security Defaults (per Compose service)

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true                    # where compatible
tmpfs:
  - /tmp
restart: unless-stopped
```

### Validation

```bash
make security-scan           # Trivy + Syft on repo
make lint                     # hadolint on any Dockerfiles
```

---

## Phase 12: GitHub Actions CI (Self-Hosted M3 Mac Runner)

**Objective:** Set up GitHub Actions workflows that run on a self-hosted M3 Mac runner. This is where the "M3 backend" connects — validation happens on the same machine class as development.

### Prerequisites — Self-Hosted Runner Setup

1. Install runner on M3 Mac: `gh runner register` (separately, user-driven)
2. Runner labels: `self-hosted, macOS, ARM64, m3, circuithq-validation`
3. No production secrets on runner
4. Least-privilege GitHub token (repo scope only)

### Workflow Files

#### `.github/workflows/00-ci-contract.yml`

Checks repo structure, no laptop deploy workflow can run automatically, no `.env.production` committed.

```yaml
on: [pull_request, push]
jobs:
  contract:
    runs-on: [self-hosted, macOS, ARM64, m3, circuithq-validation]
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/ci/ci-contract.sh
```

#### `.github/workflows/01-lint.yml`

- yamllint, markdownlint, shellcheck, shfmt, hadolint, editorconfig-checker

#### `.github/workflows/02-validate-compose.yml`

- `docker compose config` for every stack
- Check images pinned, health checks present, restart policies, no accidental port exposure

#### `.github/workflows/03-secrets.yml`

- gitleaks, no decrypted SOPS, no `.env` files, `.env.example` only placeholders

#### `.github/workflows/04-security-scan.yml`

- Trivy filesystem/config scan, Syft SBOM generation

#### `.github/workflows/05-mac-integration.yml`

- Start test stack (proxy + monitoring + one test app)
- Verify health endpoints, network isolation, Traefik routes load
- Cleanup always runs (even on failure)
- ARM64 compatibility implicitly verified (native macOS)

#### `.github/workflows/06-release-candidate.yml`

- On merge to main: generate release metadata (SHA, compose render, SBOM, change log)
- Upload artifacts
- `workflow_dispatch` with manual approval

#### `.github/workflows/07-deploy-target-disabled.yml`

- **LOCKED until explicit user approval**
- `workflow_dispatch` only
- Requires typed `I_APPROVE_LAPTOP_DEPLOY` + approval file `docs/approvals/laptop-cicd-retarget-approved.md`
- Dry-run mode before actual deploy

### CI Architecture Flow

```
M3 Mac Dev ──git push──> GitHub ──trigger──> GitHub Actions
                                                  │
                                ┌─────────────────┼──────────────────┐
                                v                 v                  v
                         00-ci-contract   01-lint   02-validate-compose
                         03-secrets       04-scan   05-mac-integration
                                                  │
                                                  v
                                          06-release-candidate
                                                  │
                                                  v (manual approval + typed confirmation)
                                          07-deploy-target (DISABLED initially)
```

### Branch Protection (GitHub Settings — User Must Configure)

- main branch: PR required, required checks pass, branch up-to-date
- Required checks: ci-contract, lint, validate-compose, secrets, security-scan, mac-integration

### Makefile → CI Parity

Every CI job has a corresponding `make` target:

```makefile
validate: lint compose-config secrets-check security-scan
lint: yamllint shellcheck markdownlint
compose-config: scripts/validate/validate-compose.sh
secrets-check: scripts/validate/validate-secrets.sh
security-scan: scripts/ci/ci-scan.sh
integration-test: scripts/test/integration-compose.sh
evidence: scripts/ci/generate-evidence.sh
```

---

## Phase 13: Manual Deployment Pipeline (Config Only — No Deploy Execution)

**Objective:** Scripts and workflow to do manual deployment to the M3 Mac target, gated by explicit approval.

### Files to Create

- `scripts/deploy/deploy.sh` — pull, decrypt, render, start, healthcheck, verify
- `scripts/deploy/preflight.sh` — pre-deploy: backup, DB dump, snapshot current state
- `scripts/deploy/healthcheck.sh` — post-deploy container health + route verification
- `scripts/deploy/verify-traffic.sh` — Cloudflare + Tailscale route checks
- `scripts/deploy/rollback.sh` — stop failed, restore previous config/secrets, start, verify
- `docs/runbooks/deploy.md`
- `docs/runbooks/rollback.md`

### Rollback Approach

- Pre-deploy snapshot: store current Git SHA, image digests, compose render, DB dump
- On failure: stop new containers → restore previous compose/config → start → verify
- Stateless services: auto-rollback allowed
- Stateful services: manual confirmation for DB migration rollback

---

## Phase 14: Add First Real Application

**Objective:** Deploy one production-quality app (e.g., a web dashboard or API) following all platform standards — to prove the stack works end-to-end locally.

### Candidate Apps (User Chooses)

- Uptime Kuma (lightweight, good test case)
- ntfy (notification server)
- A custom API or web app

### Files to Create

- `stacks/apps/<app-name>/compose.yml`
- `stacks/apps/<app-name>/README.md`
- `stacks/apps/<app-name>/config/` (if needed)
- Traefik labels for public or private route
- Authelia forward-auth if admin-facing
- SOPS-encrypted secrets if needed
- Health check, backup rule, monitoring scrape target

### Validation

```bash
make integration-test        # full stack up
curl -f https://app.circuithq.local    # via Traefik (local DNS)
docker compose ps             # all containers healthy
```

---

## Phase 15: Documentation Completion

**Objective:** Make the repo self-documenting — no tribal knowledge required to operate or recover the platform.

### Files to Create/Complete

- `docs/architecture/overview.md` — big picture with ASCII diagram
- `docs/architecture/network.md` — complete network diagram
- `docs/architecture/security.md` — security model
- `docs/architecture/tailscale.md`
- `docs/architecture/traefik.md`
- `docs/architecture/backups.md`
- `docs/architecture/monitoring.md`
- `docs/architecture/logging.md`
- `docs/architecture/disaster-recovery.md`
- `docs/architecture/scaling-roadmap.md`
- `docs/runbooks/` — all runbooks complete
- `docs/troubleshooting/` — common failures per component
- `docs/decisions/` — ADRs for every major choice

---

## Phase 16: M3 Backend Connection (Laptop Deployment Target)

**Objective:** After the user explicitly approves, retarget CI/CD to deploy to the M3 Mac (laptop) as the production target.

### Retarget Prerequisites (from §32.20)

- [ ] M3 Mac local validation stable across all phases
- [ ] User explicitly says Mac-local result is satisfactory
- [ ] Laptop OS + architecture documented
- [ ] Laptop Docker runtime documented (OrbStack, Docker Desktop, Colima)
- [ ] Laptop Tailscale connectivity tested
- [ ] Laptop deploy user is least-privilege
- [ ] Laptop secret strategy documented (SOPS + age on target)
- [ ] Dry-run deploy passes
- [ ] Rollback dry-run passes
- [ ] `laptop-production` GitHub Environment created with manual approval
- [ ] Deployment workflow requires typed `I_APPROVE_LAPTOP_DEPLOY` confirmation
- [ ] `docs/approvals/laptop-cicd-retarget-approved.md` created

### Implementation Steps

1. Enable `.github/workflows/07-deploy-target-disabled.yml` → rename to `07-deploy-laptop.yml`
2. Set GitHub Environment `laptop-production` with required reviewers
3. Add deploy script logic for macOS (homebrew paths, OrbStack Docker socket, Tailscale SSH)
4. First deploy: dry-run only
5. Second deploy: staging (separate Compose project)
6. Third deploy: production (main Compose project)
7. Post-deploy: monitoring dashboards confirm target health

---

## Validation Contract (Every Phase)

| Check | Tool/Command |
|-------|-------------|
| YAML syntax | `yamllint .` |
| Markdown format | `markdownlint docs/` |
| Shell scripts | `shellcheck scripts/**/*.sh` |
| Compose config | `docker compose -f compose/production.yml config` |
| No secret leaks | `gitleaks detect` |
| File permissions | `scripts/validate/validate-permissions.sh` |
| Container health | `docker ps --filter health=healthy` |
| Traefik routes | `curl -f http://localhost:8080/api/http/routers` |
| Prometheus targets | `curl http://localhost:9090/api/v1/targets` |
| Grafana alive | `curl -f http://localhost:3000/api/health` |
| Loki alive | `curl -f http://localhost:3100/ready` |
| Backup check | `restic check` (when repo configured) |
| Integration tests | `make integration-test` |

---

## Implementation Order Summary

| # | Phase | Duration Est. | GH Actions |
|---|-------|:-------------:|:----------:|
| 0 | Repo bootstrap | quick | No |
| 1 | Host bootstrap | quick | No |
| 2 | Tailscale config | quick | No |
| 3 | Compose foundation | medium | Contract + Lint |
| 4 | Traefik | medium | Compose + Integration |
| 5 | Cloudflare config | quick | Lint |
| 6 | SOPS + age | quick | Secrets check |
| 7 | Authelia | medium | Compose + Integration |
| 8 | Monitoring | medium | Compose + Integration |
| 9 | Logging | quick | Compose + Integration |
| 10 | Backups | medium | Lint |
| 11 | Security | medium | Security scan |
| 12 | GitHub Actions CI | medium | (All the above!) |
| 13 | Deploy pipeline | medium | Release + (disabled) Deploy |
| 14 | First real app | medium | Full CI |
| 15 | Documentation | long | Lint only |
| 16 | Laptop deployment | medium | Deploy (after approval) |

---

## Open Questions

1. **Docker runtime:** OrbStack, Docker Desktop, or Colima on the M3 Mac? (OrbStack is recommended — lightweight, fast, ARM-native)
2. **Domain:** What public domain will be used for the Cloudflare tunnel? (needed for config placeholders)
3. **M3 Mac role:** Is the M3 Mac the sole dev machine AND the deployment target, or do you have a separate server/laptop for production?
4. **Runner:** Do you want to set up the GitHub self-hosted runner on the M3 Mac, or use GitHub-hosted runners for the non-Docker checks (lint, markdown, yaml) and only Docker tests on self-hosted?
5. **First real app:** What's the first app you want to deploy? (Uptime Kuma? ntfy? Something custom?)
6. **Proxy:** Any HTTP_PROXY/HTTPS_PROXY needs on your network?

---

> **Plan complete and saved.** No files outside `.hermes/plans/` have been created or modified. Ready to execute phase-by-phase when you give the green signal.