# Security Architecture

## Overview

CircuitHQ employs a **layered security model** — ingress, transport, authentication, container, and host. No single layer is relied upon in isolation.

## Security Layers

```
Layer 1: Cloudflare Edge
  └─ WAF (OWASP rules, rate limiting, bot management)
  └─ DDoS protection
  └─ TLS termination at edge

Layer 2: Cloudflare Tunnel
  └─ No open inbound firewall ports
  └─ Outbound-only WebSocket connection
  └─ Tunnel authentication via token/credentials

Layer 3: Traefik Reverse Proxy
  └─ TLS 1.2/1.3 with strong ciphers
  └─ HSTS (1 year, preload, subdomains)
  └─ Security headers (CSP, X-Frame, XSS, Referrer-Policy)
  └─ Rate limiting (100 req/min global, 10/min auth)
  └─ IP whitelisting for admin endpoints
  └─ exposedByDefault: false

Layer 4: Authelia Authentication
  └─ MFA via TOTP + WebAuthn
  └─ RBAC (groups: admins, users)
  └─ Session management (Redis, timed expiration)
  └─ Brute-force protection (5 retries → 5min ban)
  └─ Password policy (≥12 chars, complex)

Layer 5: Container Security
  └─ Read-only filesystems where possible
  └─ Capability dropping (cap_drop: ALL)
  └─ No new privileges (no-new-privileges:true)
  └─ Log rotation (prevent disk fills)
  └─ Restart policies (unless-stopped)

Layer 6: Network Segmentation
  └─ 9 Docker networks, most internal-only
  └─ Monitoring/Logging/Database on isolated networks
  └─ Proxy network shared only with Traefik

Layer 7: Host Security
  └─ SSH disabled (Tailscale SSH only)
  └─ Firewall (default deny inbound)
  └─ Automatic security updates
  └─ Docker daemon hardening (icc=false, no-new-privileges)

Layer 8: Secret Management
  └─ Encryption at rest (SOPS + age)
  └─ Runtime secrets 0600 permissions
  └─ No secrets in Git, CI logs, or environment
  └─ Key rotation documented
```

## Compose Security Analysis

The `validate-compose-security.sh` script scans every stack's `compose.yml` for:

| Pattern | Severity | Detection |
|---------|----------|-----------|
| `privileged: true` | Warning | Container has unrestricted host access |
| Docker socket mount | Warning | Container can control Docker daemon |
| Missing restart policy | **Error** | Container won't restart on failure |
| `network_mode: host` | Warning | Container shares host network namespace |
| Missing `no-new-privileges` | Warning | Risk of privilege escalation via SUID |
| Host port binding | Warning | Potential external exposure |

All warnings are non-blocking but must be documented with justification (see exceptions table in `infra/security/README.md`).

## Permission Validation

The `validate-permissions.sh` script checks:

| File/Directory | Required Permission | Why |
|----------------|-------------------|-----|
| `~/.config/sops/age/keys.txt` | 0600 | Master encryption key |
| `acme.json` (Traefik) | 0600 | Let's Encrypt private keys |
| Shell scripts (`scripts/`) | 0755 or 0700 | Correct execution permissions |
| `.env` files (rendered) | 0600 | Runtime secrets not world-readable |
| SOPS `.sops.yaml` files | Not world-writable | Prevent tampering |
| `credentials.json` | 0600 (and not committed) | Cloudflare tunnel credentials |

## CI Security Scanning

The `ci/scripts/ci-scan.sh` script integrates:

| Tool | Purpose | Run Mode |
|------|---------|----------|
| **Trivy** | Vulnerability scanning (filesystem + config) | CI, local |
| **Syft** | SBOM generation (dependency inventory) | CI, scheduled |

Trivy scans for:
- OS package vulnerabilities (Alpine, Debian, etc.)
- Language-specific CVEs (Python, Node, Go)
- Misconfigurations (Docker, Kubernetes, Terraform)
- Exposed secrets in files

## Compliance Considerations

While CircuitHQ is a homelab, these practices align with:

- **CIS Docker Benchmark** — container hardening, daemon config
- **OWASP Top 10** — WAF, headers, auth, rate limiting
- **NIST 800-53** — AC-2 (account mgmt), SC-8 (transmission), SC-12 (crypto)
- **SOC 2** — Logical and physical access controls

## Known Gaps (Planned)

| Gap | Phase | Mitigation |
|-----|-------|-----------|
| Container image vulnerability scanning at build time | Phase 12 (CI) | Trivy in CI pipeline |
| CrowdSec integration | Phase 15 | IP ban on attack patterns |
| Secrets rotation automation | Phase 15 | cron job with restic hook |
| Audit logging (container actions) | Phase 15 | Docker event monitoring |
| Incident runbook | Phase 15 | Documented response procedures |

## Related Documents

- `infra/security/README.md` — Infrastructure-level controls
- `docs/architecture/traefik.md` — TLS, headers, rate limiting
- `docs/architecture/authentication.md` — Authelia RBAC and MFA
- `docs/runbooks/secrets.md` — Secret management procedures
- `Makefile` — `make validate` includes all security checks