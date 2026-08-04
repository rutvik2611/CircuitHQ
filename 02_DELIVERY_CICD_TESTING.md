# Delivery, CI/CD, Testing, and Rollback

> Split from `HOMELAB_PLATFORM_BLUEPRINT.md` on 2026-08-04. The original giant file is retained as an archive/source reference.

Delivery system: CI/CD, deployment pipeline, rollback, testing, M3 Mac workflow, and detailed GitHub Actions design.

## Local Table of Contents

- [10. CI/CD Architecture](#10-cicd-architecture)
- [11. Deployment Pipeline](#11-deployment-pipeline)
- [12. Rollback Workflow](#12-rollback-workflow)
- [22. Testing Strategy](#22-testing-strategy)
- [31. M3 Mac Local Development and LLM Flow Checklist](#31-m3-mac-local-development-and-llm-flow-checklist)
- [32. Detailed GitHub Actions CI/CD Design](#32-detailed-github-actions-cicd-design)

---

# 10. CI/CD Architecture

## 10.1 CI/CD goals

- Free software or free tier only.
- Validate everything before deployment.
- No automatic production deployment without explicit approval.
- Reproducible builds.
- Rollback-ready releases.
- Audit trail in Git.

## 10.2 CI/CD diagram

```text
Developer
   |
   | git commit / push
   v
Git repository
   |
   +-- Pull request checks
   |      +-- lint Markdown/YAML/shell
   |      +-- format check
   |      +-- compose config validation
   |      +-- secret leakage scan
   |      +-- container build
   |      +-- image scan
   |      +-- SBOM generation
   |      +-- integration tests
   |
   +-- Release workflow
          +-- create versioned release artifact
          +-- require manual approval
          +-- deploy through Tailscale SSH or local runner
          +-- health checks
          +-- traffic verification
          +-- rollback on failure
          +-- notify admin
```

## 10.3 Free CI options

### GitHub Actions free tier

Pros:

- Easy to start.
- Good marketplace ecosystem.
- Free for public repositories and limited free minutes for private.
- Manual approval environments available.

Cons:

- SaaS dependency.
- Private repo minutes may be limited.
- Vendor lock-in to workflow syntax.
- Requires secure remote deploy path.

Best use:

- Public or low-volume private repo.
- Initial validation workflow.
- Manual deployments through Tailscale SSH or self-hosted runner.

### Forgejo Actions

Pros:

- Free and open-source.
- Self-hosted Git + Actions-like CI.
- Good GitHub Actions compatibility direction.
- No paid SaaS dependency.

Cons:

- You operate it.
- Runner hardening required.
- Ecosystem smaller than GitHub.

Best use:

- Long-term no-SaaS GitOps-inspired platform.

### Gitea Actions

Pros:

- Mature self-hosted Git server.
- Actions-like workflows.
- Lightweight.

Cons:

- Similar self-hosting burden.
- Compatibility and feature differences vs GitHub.

Best use:

- Simple self-hosted Git + CI.

### Woodpecker CI

Pros:

- FOSS.
- Lightweight.
- Good container-native pipeline model.
- Works with Forgejo/Gitea.

Cons:

- Different pipeline syntax.
- Manual approval patterns may require careful design.

Best use:

- Self-hosted CI with explicit pipeline stages and runners.

### Drone CE

Pros:

- Container-native.
- Historically popular.

Cons:

- Community edition limitations and ecosystem concerns.
- Woodpecker is often preferred as a community fork.

Best use:

- Only if you already know Drone and its constraints.

## 10.4 Recommended CI path

| Stage | Recommendation |
|---|---|
| Day 1 | GitHub Actions if repo is already on GitHub and convenience matters |
| FOSS-first target | Forgejo + Woodpecker CI or Forgejo Actions |
| Runner location | local runner on separate machine if available; PiKVM only if resource use is acceptable |
| Deploy method | Tailscale SSH with locked deploy user, or local runner on host |
| Approval | Manual environment approval or manual `workflow_dispatch` with release tag |

---

---

# 11. Deployment Pipeline

## 11.1 Complete deployment pipeline diagram

```text
Developer
   |
   v
Git Push / Pull Request
   |
   v
Lint
   |
   v
Formatting Check
   |
   v
YAML Validation
   |
   v
Docker Compose Validation
   |
   v
Secret Validation / Secret Leak Scan
   |
   v
Docker Build
   |
   v
Container Image Scan
   |
   v
SBOM Generation
   |
   v
Integration Tests
   |
   v
Smoke Tests in Staging/Test Compose Project
   |
   v
Generate Versioned Release
   |
   v
Manual Approval Gate
   |
   v
Deploy to Production Host
   |
   v
Health Checks
   |
   v
Traffic Verification through Traefik/Cloudflare/Tailscale
   |
   +-- success --> Notify Success
   |
   +-- failure --> Rollback --> Verify Previous Version --> Notify Failure
```

## 11.2 Pipeline stages

### Stage 1: Developer

Developer changes Compose files, Traefik config, scripts, docs, or app versions.

Required local checks:

- `docker compose config`
- YAML lint
- shellcheck
- markdown lint optional
- secret scan before commit

### Stage 2: Git push

Push to feature branch. Main branch is protected.

Rules:

- Pull request required.
- CI must pass.
- Manual review for production-impacting changes.
- Secrets must never be committed unencrypted.

### Stage 3: Lint

Tools:

- `yamllint`
- `shellcheck`
- `hadolint` for Dockerfiles
- `markdownlint-cli` optional

### Stage 4: Formatting

Tools:

- `prettier` for YAML/Markdown if desired
- `shfmt` for shell scripts
- `.editorconfig`

### Stage 5: YAML validation

Validate all YAML files parse correctly.

Tools:

- `yamllint`
- `yq`
- Python `ruamel.yaml` optional

### Stage 6: Compose validation

Run:

```powershell
Docker compose -f compose\production.yml config
```

For Linux CI:

```bash
docker compose -f compose/production.yml config
```

Validation requirements:

- No missing environment variables.
- Networks declared.
- Volumes declared.
- Health checks present for critical services.
- Restart policies present.
- Images pinned to versions.

### Stage 7: Secret validation

Tools:

- `gitleaks`
- `trufflehog` optional
- `sops --decrypt --extract` checks only in secure CI context

Validate:

- No plaintext secrets.
- Required SOPS files decrypt in authorized environment.
- `.env.example` has non-secret placeholders.
- Secret file permissions are correct after deployment.

### Stage 8: Docker build

Build local custom images if any.

Principles:

- Prefer official images with pinned versions.
- Build only when necessary.
- Use multi-stage builds.
- Generate SBOM for custom images.

### Stage 9: Container scan

Tools:

- Trivy
- Grype
- Docker Scout is not required because FOSS-first design prefers Trivy/Grype.

Policy:

- Critical vulnerabilities fail unless explicitly accepted with expiration.
- High vulnerabilities require review.
- Base images updated through controlled PRs.

### Stage 10: Integration tests

Use test Compose project:

- Start minimal stack.
- Validate Traefik config loads.
- Validate service discovery labels.
- Validate health endpoints.
- Validate network isolation where testable.

### Stage 11: Smoke tests

Examples:

- `GET /healthz`
- Traefik ping endpoint.
- Grafana login page returns expected status.
- Prometheus targets endpoint available internally.
- cloudflared tunnel status healthy.

### Stage 12: Generate release

Release artifact includes:

- Git SHA.
- Compose rendered config.
- Changed files list.
- SBOMs.
- Image tags/digests.
- Migration notes.
- Rollback target.

### Stage 13: Manual approval

Production deployment requires explicit approval.

Acceptable mechanisms:

- GitHub Environments manual approval.
- Forgejo protected environments or manual workflow.
- Woodpecker manual promotion.
- Human runs `deploy.ps1`/`deploy.sh` with release tag.

### Stage 14: Deploy

Deployment steps:

1. Connect to host over Tailscale SSH.
2. Pull repo or release artifact.
3. Decrypt secrets locally on host.
4. Snapshot current config and selected volumes.
5. Render Compose config.
6. Pull new images.
7. Start/update services.
8. Wait for health checks.

### Stage 15: Health checks

Health checks must verify:

- Container health state.
- Expected ports listening internally.
- Traefik routers loaded.
- Public routes return expected HTTP status.
- Private admin routes accessible through Tailscale.
- Monitoring targets are up.

### Stage 16: Traffic verification

Verify through:

- Internal Docker network checks.
- Host checks.
- Tailscale checks.
- Cloudflare public checks.
- Traefik access logs.

### Stage 17: Rollback if failed

Rollback triggers if:

- Critical container unhealthy.
- Public service unavailable beyond threshold.
- Traefik config invalid.
- Database migration failed.
- Health checks fail.

### Stage 18: Notify success/failure

Free notification options:

- Self-hosted ntfy.
- Email through existing SMTP if available.
- Gotify.
- Matrix webhook.
- Uptime Kuma notifications.

---

---

# 12. Rollback Workflow

## 12.1 Rollback diagram

```text
Deployment Started
   |
   v
Pre-deploy Snapshot
   +-- Compose files
   +-- Config files
   +-- Secret material references
   +-- Image digests
   +-- Critical volumes/database dump
   |
   v
Deploy New Version
   |
   v
Health + Traffic Checks
   |
   +-- Pass --> Mark release successful --> Notify
   |
   +-- Fail
          |
          v
      Stop failed containers
          |
          v
      Restore previous compose/config/secrets
          |
          v
      Restore database/volume snapshot if needed
          |
          v
      Start previous containers
          |
          v
      Verify previous health
          |
          +-- Pass --> Notify rollback success
          +-- Fail --> Escalate emergency runbook
```

## 12.2 Rollback requirements

Before every production deploy:

- Store current Git SHA.
- Store current image digests.
- Render and save current Compose config.
- Snapshot config directories.
- Dump databases before migrations.
- Snapshot or restic-backup critical volumes.
- Record previous secrets version.

## 12.3 Rollback strategy by component

| Component | Rollback method |
|---|---|
| Compose config | Checkout previous Git SHA or release artifact |
| Images | Pull/run previous image digests |
| Secrets | Restore previous encrypted file or decrypted runtime file from secure snapshot |
| Traefik config | Restore previous dynamic/static config and reload |
| Database schema | Prefer backward-compatible migrations; otherwise restore dump |
| Volumes | Restore restic snapshot for affected service |
| Certificates | Restore ACME/cert files if corrupted |

## 12.4 Automatic rollback rules

Automatic rollback can be safe for stateless services. For stateful services, rollback must be conservative.

Recommended rules:

- **Stateless app failure:** automatic rollback allowed.
- **Traefik failure:** automatic rollback allowed.
- **cloudflared failure:** automatic rollback allowed.
- **Database migration failure before commit:** automatic rollback allowed.
- **Database migration completed and incompatible:** require manual recovery unless dump restore is explicitly approved.
- **Secret rotation failure:** automatic rollback to previous secret if still valid.

---

---

# 22. Testing Strategy

## 22.1 Required automated tests

| Area | Test |
|---|---|
| Docker Compose | `docker compose config` for every stack/profile |
| Traefik configuration | Static/dynamic config syntax, routers, middlewares |
| Cloudflare Tunnel | YAML syntax, ingress rules, target availability |
| Health endpoints | HTTP checks for `/healthz`, Traefik ping, app health |
| Networking | Verify expected containers share networks and forbidden pairs do not |
| DNS | Resolve public domain, internal MagicDNS, split DNS records |
| Volumes | Verify required volumes exist and mount permissions work |
| Permissions | Check secret files `0600`, ACME `0600`, scripts executable |
| Container startup | Start test stack and wait for healthy states |
| Restart policy | Assert critical services use `unless-stopped` or equivalent |
| Environment variables | Required env vars present, no placeholder secrets in prod |
| Certificates | Cert exists, not expired, SAN matches route |
| Secrets | No plaintext secrets, SOPS decrypt works in authorized environment |

## 22.2 Test environments

| Environment | Purpose |
|---|---|
| local validation | Fast syntax checks before commit |
| CI validation | Repeatable checks on PR |
| staging Compose project | Start subset of stack with separate project name |
| production smoke | Post-deploy real checks |
| restore test | Validate backups independently |

## 22.3 Compose tests

Examples:

```bash
docker compose -f compose/production.yml config >/tmp/rendered-compose.yml
docker compose -f stacks/proxy/compose.yml config >/tmp/proxy-compose.yml
```

Validate:

- no missing variables
- no invalid YAML
- no accidental host port exposure except explicitly documented local-only ports
- critical health checks exist
- networks are declared

## 22.4 Traefik tests

Validate:

- dynamic config parses
- middlewares exist
- routers reference existing middlewares
- dashboard route is protected
- `exposedByDefault=false`
- metrics endpoint is not public

## 22.5 Cloudflare Tunnel tests

Validate:

- tunnel config YAML parses
- ingress hostnames match expected public routes
- final rule returns 404 or safe default
- cloudflared container can resolve/reach Traefik

## 22.6 Networking tests

Automate checks like:

- Database container is not attached to `proxy`.
- Public app cannot reach management container.
- Traefik can reach only labeled public services.
- Prometheus can reach exporters.

## 22.7 DNS tests

Check:

- `service.example.com` resolves publicly to Cloudflare.
- Tailscale MagicDNS resolves `pikvm-prod`.
- Split DNS resolves internal names.
- AdGuard/Pi-hole upstream works.

## 22.8 Permissions tests

Check:

- `acme.json` is `0600`.
- SOPS age key is `0600`.
- secret runtime env files are `0600`.
- backup repository credentials are not world-readable.
- scripts are executable and owned correctly.

---

---

# 31. M3 Mac Local Development and LLM Flow Checklist

This implementation starts on an M3 Mac for speed and local iteration. The laptop deployment target is introduced only after the user is satisfied with local Mac validation and explicitly approves CI/CD retargeting.

The most important operating rule is: **do not mark checklist items complete until they are actually done and verified.** During work, checklist boxes remain unchecked. At the end of a session, only verified items may be marked complete, and each checked item must include evidence.

## 31.1 M3 Mac-first workflow

```text
M3 Mac local workstation
   |
   | edit, lint, validate, render Compose, smoke-test locally
   v
GitHub repository
   |
   | GitHub Actions validation using local M3 Mac self-hosted runner
   v
Release candidate artifacts
   |
   | only after explicit user approval
   v
Retarget CI/CD to laptop
   |
   | manual approval, dry-run, health checks, rollback checks
   v
Laptop deployment target
```

## 31.2 Required LLM flow checklist

The LLM should copy this checklist into each implementation session. It must keep boxes unchecked until final verification.

```markdown
## Session checklist - keep unchecked until final verification

- [ ] Question gate completed or explicitly deferred as not needed for this phase.
- [ ] Account, token, domain, DNS, Tailscale, GitHub, notification, backup, and proxy needs identified without exposing secrets.
- [ ] Proxy requirements checked: HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, and reverse-proxy/domain settings.
- [ ] M3 Mac local-development impact checked, including Apple Silicon/ARM64 compatibility.
- [ ] Files to change identified.
- [ ] Existing files read before editing.
- [ ] Minimal changes implemented.
- [ ] No plaintext secrets created.
- [ ] Local validation run on the M3 Mac or documented as not applicable.
- [ ] CI validation path identified.
- [ ] Config syntax validated where applicable.
- [ ] Tests or smoke checks run where applicable.
- [ ] Evidence artifacts/logs identified.
- [ ] Done criteria verified with evidence.
- [ ] Final summary includes checked items only after verification.
- [ ] Next session not started; waiting for explicit user green signal.
```

## 31.3 LLM stop conditions

Stop and ask the user before continuing if:

- A real secret, token, password, API key, private key, tunnel credential, or GitHub runner token is required.
- A domain, DNS zone, Tailscale tailnet, GitHub repo, or account ID is required and unknown.
- A command could be destructive on the M3 Mac or future laptop.
- A proxy may be required but proxy settings are unknown.
- A step would expose any service publicly.
- A step would retarget CI/CD to the laptop without explicit approval.
- A validation step fails.
- The next prompt/session would start without the user's green signal.

## 31.4 Final evidence table template

At the end of every session, include an evidence table. A row can be checked only if there is real evidence.

```markdown
## Final verification evidence

| Item | Status | Evidence |
|---|---|---|
| Question gate completed | [ ] / [x] | Questions asked, answers received, or reason not needed |
| Proxy requirements checked | [ ] / [x] | User answer, placeholder config, or documented deferral |
| Files changed | [ ] / [x] | File paths |
| Existing files read first | [ ] / [x] | File paths read |
| Secrets protected | [ ] / [x] | No plaintext secrets; placeholders/SOPS only |
| Local Mac validation | [ ] / [x] | Command and result, or documented not applicable |
| CI validation path | [ ] / [x] | Workflow/job name or documented future step |
| Config validation | [ ] / [x] | Command and result |
| Tests/smoke checks | [ ] / [x] | Command and result |
| Done criteria met | [ ] / [x] | Evidence summary |
| Waiting for green signal | [ ] / [x] | Explicit statement that next session is not started |
```

---

---

# 32. Detailed GitHub Actions CI/CD Design

This is the detailed CI/CD plan for stability and ease of development. The current choice is **GitHub Actions with a separately hosted local M3 Mac self-hosted runner**. The runner validates the repository quickly and safely. The laptop is not a deployment target until the user explicitly approves the retargeting gate.

## 32.1 CI/CD non-negotiable rules

| Rule | Requirement |
|---|---|
| Every change is validated | No step is complete without local or CI evidence. |
| Every PR has checks | PRs must pass required GitHub checks before merge. |
| Every failure stops progress | Do not move to the next prompt/session while CI is red. |
| Every skipped test is explained | Skips require a reason and follow-up if still needed. |
| Every deployment is manual | Nothing deploys to production automatically. |
| Every release has artifacts | Rendered configs, reports, SBOMs, and rollback metadata are preserved. |
| Secrets are protected | No plaintext secrets in repo, logs, artifacts, or workflow output. |
| Laptop deploy is disabled now | Laptop deployment is introduced only after explicit user approval. |

## 32.2 CI/CD architecture

```text
Developer on M3 Mac
   |
   | local scripts: make validate, make test, make evidence
   v
GitHub repo
   |
   | push / pull request
   v
GitHub Actions control plane
   |
   +-- CI contract checks
   +-- lint checks
   +-- Compose rendering
   +-- secret leak checks
   +-- security scans
   +-- M3 Mac Docker integration tests
   +-- release candidate artifact generation
   |
   +-- laptop deployment workflow
          disabled until explicit approval
```

## 32.3 Runner strategy

### Current runner: M3 Mac self-hosted validation runner

| Item | Value |
|---|---|
| Runner type | GitHub Actions self-hosted runner |
| Host | Local M3 Mac, hosted separately from production |
| Purpose | Fast validation, linting, Compose rendering, integration tests, release artifacts |
| Suggested labels | `self-hosted`, `macOS`, `ARM64`, `m3`, `homelab-validation` |
| Docker runtime | Docker Desktop, OrbStack, Colima, or user-approved runtime |
| Trust level | Trusted validation machine, not production target |
| Production secrets | Avoid initially |
| Public exposure | None |

### Future target: laptop

| Item | Rule |
|---|---|
| Activation | Only after explicit user approval |
| Role | Deployment target or deployment runner |
| Access | Tailscale SSH, local runner, or remote Docker context |
| Required proof | Dry-run deploy, health check, rollback dry-run, secret strategy, proxy check |

## 32.4 M3 Mac runner hardening checklist

- Use a dedicated macOS user for the runner if practical.
- Do not run the runner as an administrator unless specifically required.
- Do not store production secrets in the runner workspace.
- Do not allow untrusted fork pull requests to execute on the self-hosted runner.
- Use branch protection and required checks.
- Use GitHub Environments for manual approval gates.
- Use least-privilege `permissions:` in every workflow.
- Use `timeout-minutes:` in every job.
- Use `concurrency:` to prevent overlapping jobs.
- Use cleanup steps with `if: always()` for Docker integration tests.
- Upload failure logs as artifacts.
- Keep runner software and Docker runtime updated on a controlled schedule.
- Keep laptop deployment credentials away from the Mac runner until the retarget phase.

## 32.5 Repository branch protection

Protect `main` with:

- Pull request required before merge.
- Required status checks before merge.
- Branch must be up to date before merge.
- Conversation resolution required.
- Force pushes blocked.
- Branch deletion blocked.
- Reviews required when practical.

Required checks should be stable and human-readable:

```text
ci-local-contract
lint-yaml-markdown-shell
validate-compose
validate-secrets
scan-config
mac-compose-integration
ci-evidence-summary
```

## 32.6 GitHub Environments

| Environment | Purpose | Approval |
|---|---|---|
| `local-mac-validation` | M3 Mac validation jobs | No production approval |
| `release-candidate` | Generate release artifacts | Optional manual approval |
| `laptop-staging` | Future laptop dry-run/staging | Manual approval required |
| `laptop-production` | Future laptop production | Manual approval required |

The `laptop-production` environment should not be used until the laptop retarget checklist is complete.

## 32.7 Secrets strategy

Initial rule: **do not put production secrets into GitHub Actions unless a phase explicitly needs them and a protected environment exists.**

| Phase | Secret handling |
|---|---|
| Local Mac development | Placeholders or local SOPS/age only |
| Pull request validation | No production secrets |
| M3 Mac integration tests | Local test placeholders only |
| Release candidate | No production secrets unless signing is added later |
| Laptop staging | Protected environment secrets or SOPS on target |
| Laptop production | Prefer SOPS on laptop target; GitHub Environment secrets only if justified |

Secret rules:

- Never echo secrets.
- Never upload decrypted secrets as artifacts.
- Never run production-secret jobs on untrusted PRs.
- Use scoped Cloudflare tokens, never global keys.
- Use short-lived Tailscale auth keys only when required.
- Prefer target-side SOPS decryption over sending secrets through CI.

## 32.8 Proxy support

The CI design must support networks that require proxy settings.

Ask and document whether these are needed:

- `HTTP_PROXY`
- `HTTPS_PROXY`
- `NO_PROXY`
- Docker daemon proxy
- Docker build proxy args
- Git proxy
- Homebrew proxy on macOS
- npm/pnpm/yarn proxy
- pip/Poetry proxy
- GitHub runner service proxy

Recommended `NO_PROXY` baseline:

```text
localhost,127.0.0.1,::1,.local,.test,.internal,home.arpa,lab.internal,100.64.0.0/10,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

Do not hardcode proxy credentials. Use local runner environment variables or GitHub Environment secrets only when required.

## 32.9 Local and CI parity

Every CI check should have a local command so failures are easy to reproduce on the M3 Mac.

Recommended developer commands:

```bash
make validate
make lint
make compose-config
make secrets-check
make security-scan
make integration-test
make evidence
```

Recommended script layout:

```text
scripts/ci/ci-contract.sh
scripts/ci/ci-lint.sh
scripts/ci/ci-scan.sh
scripts/ci/generate-evidence.sh
scripts/validate/validate-all.sh
scripts/validate/validate-yaml.sh
scripts/validate/validate-markdown.sh
scripts/validate/validate-shell.sh
scripts/validate/validate-compose.sh
scripts/validate/validate-secrets.sh
scripts/validate/validate-traefik.sh
scripts/validate/validate-cloudflared.sh
scripts/validate/validate-networks.sh
scripts/validate/validate-permissions.sh
scripts/test/integration-compose.sh
scripts/test/smoke-local.sh
scripts/test/cleanup-compose.sh
```

## 32.10 Workflow layout

Recommended GitHub Actions workflow files:

```text
.github/workflows/
  00-ci-contract.yml
  01-lint.yml
  02-validate-compose.yml
  03-secrets.yml
  04-security-scan.yml
  05-mac-integration.yml
  06-release-candidate.yml
  07-deploy-laptop-disabled-until-approved.yml
```

## 32.11 Workflow details

### `00-ci-contract.yml`

Purpose:

- Prove required directories and scripts exist.
- Prove the laptop deployment workflow is disabled until approval.
- Prove no plaintext production env files exist.
- Publish a CI evidence summary.

Required checks:

- `README.md` exists.
- `docs/`, `scripts/`, `compose/`, `stacks/`, `secrets/`, and `.github/workflows/` exist when applicable.
- No `.env.production` committed.
- No deployment workflow can run without manual approval.

### `01-lint.yml`

Purpose:

- YAML, Markdown, shell, Dockerfile, and EditorConfig checks.

Tools:

- `yamllint`
- `markdownlint-cli` or `markdownlint-cli2`
- `shellcheck`
- `shfmt`
- `hadolint`
- `editorconfig-checker`

### `02-validate-compose.yml`

Purpose:

- Render Compose configs and detect unsafe runtime configuration.

Required checks:

- `docker compose config` succeeds.
- No accidental public `ports:` mappings unless documented.
- Databases are not attached to `proxy`.
- Critical services have restart policies.
- Critical services have health checks.
- Images are version-pinned.
- Required networks and volumes are declared.

### `03-secrets.yml`

Purpose:

- Prevent secret leaks and enforce SOPS/placeholder patterns.

Required checks:

- `gitleaks` passes.
- No decrypted SOPS files are committed.
- No real `.env` files are committed.
- `.env.example` files contain placeholders only.
- SOPS files follow naming conventions.

### `04-security-scan.yml`

Purpose:

- Scan filesystem, configuration, and images where available.

Tools:

- Trivy filesystem/config scan.
- Syft SBOM generation.
- Grype optional vulnerability scan.
- SARIF upload optional.

### `05-mac-integration.yml`

Purpose:

- Run Docker Compose integration checks on the M3 Mac runner.

Required checks:

- Docker runtime available.
- Compose available.
- ARM64 image compatibility checked.
- Test stack starts.
- Health endpoints pass.
- Network isolation checks pass.
- Logs captured on failure.
- Cleanup always runs.

### `06-release-candidate.yml`

Purpose:

- Generate release evidence without deployment.

Artifacts:

- Git SHA.
- changed files.
- rendered Compose config.
- validation reports.
- image list/digests where available.
- SBOM.
- rollback metadata.
- release notes.

### `07-deploy-laptop-disabled-until-approved.yml`

Purpose:

- Placeholder for future laptop deployment.
- Must remain guarded until explicit approval.

Required guards:

- `workflow_dispatch` only.
- Protected `laptop-production` environment.
- Required reviewer approval.
- Explicit typed input such as `I_APPROVE_LAPTOP_DEPLOY`.
- Presence of `docs/approvals/laptop-cicd-retarget-approved.md`.
- Dry-run first.

## 32.12 Reference workflow skeletons

### Lint workflow skeleton

```yaml
name: 01 Lint

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: lint-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: lint-yaml-markdown-shell
    runs-on: [self-hosted, macOS, ARM64, m3, homelab-validation]
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Show runner context
        run: |
          uname -a
          git --version
      - name: Run lint script
        run: ./scripts/ci/ci-lint.sh
```

### Compose validation skeleton

```yaml
name: 02 Validate Compose

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: compose-${{ github.ref }}
  cancel-in-progress: true

jobs:
  compose:
    name: validate-compose
    runs-on: [self-hosted, macOS, ARM64, m3, homelab-validation]
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - name: Verify Docker
        run: |
          docker version
          docker compose version
      - name: Render Compose configs
        run: ./scripts/validate/validate-compose.sh
      - name: Upload rendered Compose evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: compose-rendered-${{ github.run_id }}
          path: artifacts/compose/
          if-no-files-found: warn
          retention-days: 14
```

### M3 Mac integration skeleton

```yaml
name: 05 M3 Mac Integration

on:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: mac-integration-${{ github.ref }}
  cancel-in-progress: true

jobs:
  integration:
    name: mac-compose-integration
    runs-on: [self-hosted, macOS, ARM64, m3, homelab-validation]
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Show platform
        run: |
          uname -m
          docker version
          docker compose version
      - name: Run integration tests
        run: ./scripts/test/integration-compose.sh
      - name: Capture Docker diagnostics
        if: always()
        run: |
          mkdir -p artifacts/docker
          docker ps -a > artifacts/docker/containers.txt || true
          docker images > artifacts/docker/images.txt || true
          docker network ls > artifacts/docker/networks.txt || true
      - name: Cleanup test stack
        if: always()
        run: ./scripts/test/cleanup-compose.sh
      - name: Upload integration evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: mac-integration-${{ github.run_id }}
          path: artifacts/
          if-no-files-found: warn
          retention-days: 14
```

### Laptop deployment guard skeleton

```yaml
name: 07 Deploy Laptop - Disabled Until Approved

on:
  workflow_dispatch:
    inputs:
      confirm_laptop_deploy:
        description: Type I_APPROVE_LAPTOP_DEPLOY to continue
        required: true
        type: string
      dry_run:
        description: Run deployment in dry-run mode
        required: true
        default: true
        type: boolean

permissions:
  contents: read

concurrency:
  group: laptop-deploy
  cancel-in-progress: false

jobs:
  guard:
    name: laptop-deploy-approval-guard
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - name: Enforce explicit approval
        run: |
          test "${{ inputs.confirm_laptop_deploy }}" = "I_APPROVE_LAPTOP_DEPLOY"
          test -f docs/approvals/laptop-cicd-retarget-approved.md
```

## 32.13 Evidence artifacts

Every important workflow should publish evidence that the user can inspect.

| Artifact | Produced by | Purpose |
|---|---|---|
| `lint-report-*` | lint | Lint results |
| `compose-rendered-*` | Compose validation | Exact rendered Compose config |
| `secrets-validation-*` | secret checks | Secret leak and placeholder validation |
| `security-scan-*` | security scan | Trivy/Grype reports |
| `sbom-*` | security/release | SBOM for custom images/filesystem |
| `mac-integration-*` | M3 integration | Docker status, logs, network info |
| `release-candidate-*` | release | Git SHA, image digests, config, rollback metadata |
| `deploy-dry-run-*` | future deploy | Laptop preflight and dry-run result |

Artifacts must never contain decrypted secrets.

## 32.14 User checking workflow

For every PR or CI run, the user should check:

1. All required GitHub checks are green.
2. The CI evidence summary exists.
3. Rendered Compose artifact exists if Compose files changed.
4. Secret validation artifact exists if secrets/config changed.
5. M3 Mac integration artifact exists if runtime behavior changed.
6. No laptop deployment workflow ran automatically.
7. No real secrets appear in logs.
8. Any skipped test has a documented reason.
9. Any warning has a follow-up task.

## 32.15 Validation contract for every step

Before implementing a step, define the validation contract:

```markdown
## Validation contract for this step

- Change being made:
- Files expected to change:
- Local validation command:
- CI validation job:
- Smoke test:
- Rollback or cleanup command:
- Evidence artifact expected:
- Done criteria:
```

No step is complete until its validation contract is satisfied.

## 32.16 Required validation by change type

| Change type | Required local validation | Required CI validation |
|---|---|---|
| Markdown docs | markdown lint, link sanity | lint |
| YAML config | YAML parse/lint | lint + config validation |
| Compose file | `docker compose config` | validate-compose + security checks |
| Traefik config | render config, start test stack | validate-compose + mac integration |
| Cloudflare tunnel config | YAML parse, ingress sanity | cloudflared validation |
| Secret template | secret scan, placeholder check | validate-secrets |
| Shell script | shellcheck, shfmt, dry-run | lint + script test |
| Dockerfile | hadolint, build | security scan + integration |
| Monitoring config | promtool if available | monitoring validation |
| Backup script | shellcheck, dry-run | backup validation |
| Deploy script | shellcheck, dry-run | deploy dry-run only |
| Rollback script | shellcheck, dry-run | rollback dry-run only |

## 32.17 Stability controls

- Use `timeout-minutes` on every job.
- Use `concurrency` groups.
- Use `cancel-in-progress: true` for validation.
- Use `cancel-in-progress: false` for deploy.
- Use cleanup steps with `if: always()`.
- Upload logs on failure.
- Keep artifact retention short for PRs and longer for releases.
- Pin tools or install deterministic versions.
- Avoid `latest` tags unless intentionally testing update behavior.
- Separate required checks from optional checks.
- Document every skipped check.

## 32.18 Ease-of-development controls

- Local `make validate` should run the same scripts as CI.
- CI errors should show the local command to reproduce.
- Heavy integration tests should run only when relevant files change.
- Job names should be stable.
- Artifacts should be named consistently.
- Mac-specific behavior should be documented.
- ARM64 compatibility issues should explain the fix.
- CI should fail fast for syntax errors and collect diagnostics for runtime failures.

## 32.19 Path filters for speed

| Paths changed | Workflows |
|---|---|
| `docs/**`, `README.md` | docs lint |
| `compose/**`, `stacks/**` | lint, Compose validation, security, integration |
| `scripts/**` | shell lint, script tests |
| `secrets/**`, `.sops.yaml` | secret validation |
| `.github/workflows/**`, `ci/**` | all CI contract checks |
| `infra/tailscale/**` | policy validation if available |
| `infra/cloudflare/**` | tunnel/DNS config validation |

Path filters must not skip security checks for files that affect deployment.

## 32.20 Laptop retargeting checklist

Do not retarget CI/CD to the laptop until all of this is true:

- M3 Mac local validation is stable.
- User explicitly says the Mac-local result is satisfactory.
- Laptop OS and architecture are documented.
- Laptop Docker runtime is documented.
- Laptop Tailscale connectivity is tested if used.
- Laptop deploy user is least-privilege.
- Laptop secret strategy is documented.
- Laptop proxy requirements are documented.
- Dry-run deploy passes.
- Rollback dry-run passes.
- `laptop-production` GitHub Environment has manual approval.
- Deployment workflow requires explicit typed confirmation.

## 32.21 CI/CD failure response

When CI fails:

1. Stop; do not move to the next prompt.
2. Read the failing job log.
3. Classify the failure: code, config, tool, runner, network, proxy, architecture, or flaky dependency.
4. Fix root cause.
5. Rerun the smallest relevant local command.
6. Rerun CI.
7. Update docs/runbooks if the failure teaches an operational lesson.
8. Include failure and fix evidence in the final summary.

## 32.22 CI/CD definition of done

CI/CD work is not done until:

- Workflows exist or are documented for the current phase.
- Local Mac validation commands exist.
- CI uses the same scripts as local validation.
- Required checks are documented.
- Secrets are protected.
- Proxy support is considered.
- Artifacts are generated.
- User can inspect clear GitHub checks.
- Laptop deploy remains disabled until approved.
- Final summary includes exact evidence.

---

---
