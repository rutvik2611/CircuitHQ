# Cloudflare Tunnel — DNS, Setup, Token Handling, and Recovery

This document describes how Cloudflare Tunnel (cloudflared) integrates with CircuitHQ's ingress architecture.

## Architecture

```
                        ┌──────────────┐
                        │  End User     │
                        └──────┬───────┘
                               │ HTTPS
                               ▼
                    ┌──────────────────┐
                    │  Cloudflare Edge │
                    │  (CDN / WAF)     │
                    └──────┬───────────┘
                           │ Cloudflare Tunnel
                           │ (outbound WebSocket)
                           ▼
                    ┌──────────────────┐
                    │  cloudflared      │
                    │  (Docker on host) │
                    └──────┬───────────┘
                           │ HTTP (internal)
                           ▼
                    ┌──────────────────┐
                    │  Traefik          │
                    │  (TLS, routing)   │
                    └──────┬───────────┘
                           │
                           ▼
                    ┌──────────────────┐
                    │  Upstream App     │
                    └──────────────────┘
```

**Key points:**
- cloudflared makes an **outbound** connection to Cloudflare — no inbound firewall ports required
- Traefik terminates TLS (Let's Encrypt) and handles all routing/middleware internally
- Cloudflare Tunnel is the **only** public ingress path — port 80/443 should not be exposed

## DNS Records

Cloudflare Tunnel uses a **CNAME** record pointing to the tunnel endpoint (not the origin IP).

| Record | Type | Target | Proxy Status |
|--------|------|--------|-------------|
| `@` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied (orange cloud) |
| `www` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied |
| `app` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied |
| `traefik` | CNAME | `<tunnel-id>.cfargotunnel.com` | Proxied |

**Note:** The `<tunnel-id>.cfargotunnel.com` target is generated when you create a tunnel in the Cloudflare Zero Trust dashboard.

## Prerequisites

1. **Cloudflare account** with a domain added (DNS managed by Cloudflare)
2. **cloudflared CLI** installed locally (for tunnel creation)
3. **Docker** with the cloudflared service defined in `stacks/proxy/cloudflared/compose.yml`

## Setup

### Step 1: Install cloudflared (locally, for admin operations)

```bash
# macOS
brew install cloudflared

# Linux
curl -L https://github.com/cloudflare/cloudflare-warp/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
```

### Step 2: Authenticate

```bash
cloudflared tunnel login
# Opens a browser — authenticate with your Cloudflare account
```

### Step 3: Create the tunnel

```bash
cloudflared tunnel create circuithq
# Produces: ~/.cloudflared/<tunnel-id>.json (credentials file)
# Take note of the tunnel ID printed
```

### Step 4: Configure DNS

On the Cloudflare Dashboard, add CNAME records pointing to `<tunnel-id>.cfargotunnel.com`

Or use the CLI:

```bash
cloudflared tunnel route dns circuithq app.YOUR-DOMAIN.com
cloudflared tunnel route dns circuithq traefik.YOUR-DOMAIN.com
```

### Step 5: Copy credentials

```bash
cp ~/.cloudflared/<tunnel-id>.json stacks/proxy/cloudflared/credentials.json
```

**DO NOT commit credentials.json.** It is already in `.gitignore` or will be during the SOPS phase.

### Step 6: Configure ingress rules

Edit `stacks/proxy/cloudflared/config.yml.template`, save as `config.yml`:

```bash
cp stacks/proxy/cloudflared/config.yml.template stacks/proxy/cloudflared/config.yml
# Edit config.yml — replace YOUR_TUNNEL_ID and YOUR-DOMAIN.com
```

### Step 7: Deploy

```bash
cd stacks/proxy
docker compose -f cloudflared/compose.yml up -d

# Verify tunnel is running
docker compose -f cloudflared/compose.yml logs cloudflared

# Check tunnel status
docker exec circuithq-cloudflared cloudflared tunnel status
```

Verify end-to-end:

```bash
curl -k https://app.YOUR-DOMAIN.com
```

## Token Handling

The tunnel credentials (`credentials.json`) are the **most sensitive secret** in this stack — they grant tunnel access to your Cloudflare account.

### Security Rules

1. **Never commit** credentials.json to git
2. **Never copy** credentials.json to untrusted machines
3. **Rotate** credentials if exposed

### Storage Options (in priority order)

| Method | How | Security |
|--------|-----|----------|
| **TUNNEL_TOKEN env var** | Create token in Zero Trust dashboard, pass as env | Best — no file on disk |
| **Docker secrets** | Mount as docker secret | Good — ephemeral |
| **credentials.json** | Mount bind mount | Acceptable — file on disk |
| **SOPS (Phase 6)** | Encrypt with age key | Best for git — encrypted at rest |

### Token Rotation

```bash
# Revoke old credentials
cloudflared tunnel token circuithq

# Create new token in Zero Trust dashboard → Networks → Tunnels → circuithq → Configure → Token
# Then update the environment variable or config
docker compose -f stacks/proxy/cloudflared/compose.yml restart
```

## Recovery

### Tunnel is disconnected

```bash
# Check logs
docker compose -f stacks/proxy/cloudflared/compose.yml logs --tail=50

# Restart the container
docker compose -f stacks/proxy/cloudflared/compose.yml restart

# Verify
docker compose -f stacks/proxy/cloudflared/compose.yml ps
```

### Credentials are corrupted or expired

```bash
# Revoke and recreate tunnel
cloudflared tunnel delete circuithq
cloudflared tunnel create circuithq

# Re-copy credentials
cp ~/.cloudflared/<new-tunnel-id>.json stacks/proxy/cloudflared/credentials.json

# Update config.yml with new tunnel ID
# Redo DNS routing
cloudflared tunnel route dns circuithq app.YOUR-DOMAIN.com

# Restart
docker compose -f stacks/proxy/cloudflared/compose.yml up -d
```

### DNS changes not propagating

- Verify DNS record is **Proxied** (orange cloud) in Cloudflare dashboard
- Wait up to 5 minutes for Cloudflare global propagation
- Check: `dig +short app.YOUR-DOMAIN.com`

### Cloudflare says "Tunnel Not Found"

- Verify the tunnel exists: `cloudflared tunnel list`
- Verify credentials.json contains a valid tunnel ID
- Regenerate credentials: `cloudflared tunnel token circuithq > credentials.json`

### Fallback Access

If Cloudflare Tunnel is down, access services via:

- **Tailscale:** Direct SSH and `traefik.circuithq.internal` dashboard
- **Local network:** Direct IP-based access on the LAN

## Validation

```bash
# Run validation script
bash scripts/validate/validate-cloudflared.sh
```

## Reference

- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [cloudflared Docker Image](https://hub.docker.com/r/cloudflare/cloudflared)
- [Tunnel Configuration](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/configure-tunnels/local-management/configuration-file/)
- [CircuitHQ Traefik Architecture](../docs/architecture/traefik.md)