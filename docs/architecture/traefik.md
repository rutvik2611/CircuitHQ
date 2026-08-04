# Traefik Architecture

Traefik is the **reverse proxy and ingress gateway** for CircuitHQ. Every web service — public or private — routes through Traefik.

## Role

```
Internet / Cloudflare Tunnel
        │
        ▼
   ┌────────┐
   │ Traefik │  (:80 → :443 redirect, :443 TLS termination)
   └────┬───┘
        │
   ┌────┴─────────────────────┐
   │ circuithq-proxy network  │
   └────┬─────────────────────┘
        │
   ┌────┴───┐   ┌────┴───┐   ┌────┴───┐
   │ App A  │   │ App B  │   │ App C  │
   └────────┘   └────────┘   └────────┘
```

## Key Design Decisions

### 1. `exposedByDefault: false`

The most important security rule. Services are **not** automatically exposed to the internet. Each service must opt in with a `traefik.enable=true` Docker label. This prevents accidental exposure of new containers.

### 2. ACME / Let's Encrypt

- **Certificate resolver:** `letsencrypt` (production)
- **Challenge:** HTTP-01 (port 80 redirects to port 443)
- **Key type:** EC256 (elliptic curve)
- **Storage:** Shared volume `circuithq-traefik-acme`
- **Staging URL** available for testing (commented in `static.yml`)

### 3. Dashboard

- **Host:** `traefik.circuithq.internal`
- **TLS:** Required (Let's Encrypt)
- **Access:** Restricted to Tailscale (`100.64.0.0/10`) and private LANs via `dashboard-auth` IP whitelist middleware
- **Not accessible** from the public internet

### 4. Middleware Chains

| Chain | Includes | Use Case |
|-------|----------|----------|
| `public-chain` | `secHeaders` + `rateLimit` | Public internet-facing apps |
| `auth-chain` | `secHeaders` + `rateLimit` + `auth-forward` | Apps behind Authelia (private) |
| `dashboard-auth` | `ipWhiteList` | Traefik dashboard only |

### 5. Network Topology

Traefik connects to three Docker networks:

| Network | Purpose |
|---------|---------|
| `circuithq-proxy` | Ingress from Traefik to upstream services |
| `circuithq-monitoring` | Prometheus metrics scraping (port 8080) |
| `circuithq-security` | Forward auth communication with Authelia |

### 6. Metrics / Monitoring

- Prometheus metrics exposed on the `traefik` entrypoint (port 8080)
- Only accessible within the `circuithq-monitoring` internal network
- Standard HTTP buckets: 0.1, 0.3, 1.2, 5.0 seconds

### 7. TLS Security

- Minimum TLS 1.2 (default profile), TLS 1.3 only (`modern` profile)
- Strong cipher suites (AEAD, ECDHE, ChaCha20-Poly1305)
- ECDSA curves: P521, P384, P256
- HSTS: 1 year, preload, include subdomains

## Entrypoints

| Name | Port | Usage |
|------|------|-------|
| `web` | 80 | HTTP → HTTPS redirect |
| `websecure` | 443 | TLS termination, all routed services |
| `traefik` | 8080 | Dashboard + Prometheus metrics (internal only) |

## Dependencies

- Docker socket (`/var/run/docker.sock`) — service discovery
- Let's Encrypt — automated TLS certificates
- Authelia (Phase 7) — forward authentication for private apps
- Cloudflare Tunnel (Phase 5) — public internet ingress

## Files

```
stacks/proxy/
├── compose.yml                          # Docker Compose service definition
└── traefik/
    ├── static.yml                       # Static configuration (startup)
    └── dynamic/
        ├── middlewares.yml              # Middleware chain definitions
        ├── tls.yml                      # TLS options and cipher settings
        ├── security-headers.yml         # Detailed HTTP security headers
        └── rate-limits.yml              # Rate limiting profiles
```