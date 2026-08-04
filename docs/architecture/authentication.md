# Authentication Architecture — Authelia + Traefik ForwardAuth

## Overview

Authelia provides **single sign-on (SSO) authentication** for all CircuitHQ web services. It integrates with Traefik via **forward authentication** (forward-auth).

```
User → Cloudflare Tunnel → Traefik
                               │
                         ┌─────┴─────┐
                         │ Forward-  │
                         │ Auth      │
                         │ (401 →    │
                         │ redirect) │
                         └─────┬─────┘
                               │
                    ┌──────────┴──────────┐
                    │     Authelia         │
                    │  (auth.circuithq.    │
                    │   internal)          │
                    ├─────────────────────┤
                    │  Redis (sessions)    │
                    │  SQLite (storage)    │
                    └─────────────────────┘
```

## Components

| Component | Purpose | Image |
|-----------|---------|-------|
| **Authelia** | Authentication engine, MFA, access control | `authelia/authelia:4.38` |
| **Redis** | Session storage (ephemeral, fast) | `redis:7-alpine` |

## Authentication Flow

1. **User requests** `https://app.circuithq.internal`
2. **Traefik** receives the request, applies `auth-chain` middleware
3. **auth-chain** calls the `auth-forward` middleware → sends request to Authelia at `http://authelia:9091/api/authz/forward-auth`
4. **Authelia** checks for a valid session cookie:
   - **No session** → Returns 401 → Traefik redirects to Authelia login (`auth.circuithq.internal`)
   - **Valid session, MFA not enrolled/enabled** → Returns 200 (one_factor policy)
   - **Valid session, MFA pending** → Redirects to Authelia 2FA page
   - **Valid session, MFA verified** → Returns 200 → Traefik forwards to upstream service
5. **Authelia** sets session cookies and redirects back to the original URL

## Access Policies

| Level | Policy | MFA Required | Services |
|-------|--------|-------------|----------|
| **Public** | `bypass` | No | auth.circuithq.internal, status.circuithq.internal |
| **Internal** | `one_factor` | No | `*.app.circuithq.internal` (user apps) |
| **Admin** | `two_factor` | **Yes** (TOTP/WebAuthn) | traefik, grafana, prometheus, loki dashboards |
| **Internal-only** | `two_factor` | **Yes** | `*.internal.circuithq.internal` |
| **Default** | `deny` | — | Everything else |

## MFA Configuration

**TOTP (Time-based One-Time Password):**
- Issuer: `CircuitHQ`
- Period: 30 seconds
- Algorithm: SHA1
- Digits: 6
- Skew: ±1 period

**WebAuthn / Passkeys:**
- Enabled (in addition to TOTP)
- Attestation: indirect
- Passkey login: enabled

## Networks

| Network | Services | Purpose |
|---------|----------|---------|
| `circuithq-proxy` | Authelia ↔ Traefik | Forward auth requests |
| `circuithq-security` | Authelia ↔ Redis | Session storage (internal) |

## Secrets

All secrets are managed via **SOPS + age** and stored in `secrets/production/authelia.sops.yaml`:

| Secret | Purpose | Min Length |
|--------|---------|-----------|
| `jwt_secret` | Password reset tokens | 64 chars |
| `session_secret` | Session cookie encryption | 64 chars |
| `storage_encryption_key` | SQLite encryption (local storage) | 32 bytes (hex) |
| `smtp_password` | SMTP authentication (optional) | — |

## User Database

Users are defined in `stacks/auth/authelia/users_database.yml`. The production version is SOPS-encrypted.

**Password hashing:**
```bash
docker run authelia/authelia:4.38 authelia hash-password 'your-password'
# Output: $argon2id$v=19$m=65536,t=3,p=4$...
```

**Groups:**
| Group | Access Level |
|-------|-------------|
| `admins` | Full admin access to all dashboards |
| `users` | Access to user-facing apps only |

## Directory Structure

```
stacks/auth/
├── compose.yml                          # Authelia + Redis services
└── authelia/
    ├── configuration.yml                # Main Authelia config
    ├── users_database.yml               # Users and password hashes
    └── access_rules.yml                 # Per-service access policies

secrets/production/
├── authelia.sops.yaml                   # Encrypted secrets
└── ...

docs/
├── architecture/authentication.md       # This file
└── runbooks/authentication.md           # Operations guide
```