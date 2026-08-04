# Cloudflare Tunnel Runbook

## Prerequisites

- Cloudflare account with domain added
- Cloudflare Tunnel created in Zero Trust dashboard
- Docker and Docker Compose installed
- Network exists: `circuithq-proxy`
- Traefik stack is running (Phase 4)

## Deploy

```bash
# 1. Set up tunnel config (first time only)
cd stacks/proxy
cp cloudflared/config.yml.template cloudflared/config.yml
# Edit config.yml — replace YOUR_TUNNEL_ID and YOUR-DOMAIN.com

# 2. Copy credentials (see infra/cloudflare/README.md for generation)
# cp ~/.cloudflared/<tunnel-id>.json cloudflared/credentials.json
# OR set TUNNEL_TOKEN env var

# 3. Start tunnel
docker compose -f cloudflared/compose.yml up -d

# 4. Verify
docker compose -f cloudflared/compose.yml ps
docker compose -f cloudflared/compose.yml logs --tail=20
docker exec circuithq-cloudflared cloudflared tunnel status
```

## Health Check

```bash
# Container health
docker ps --filter name=circuithq-cloudflared --format "{{.Status}}"

# Tunnel status
docker exec circuithq-cloudflared cloudflared tunnel status

# Internal metrics
curl -s http://localhost:2000/metrics | head -15

# End-to-end (via Cloudflare edge)
curl -s -o /dev/null -w "%{http_code}" https://app.YOUR-DOMAIN.com
```

## Logs

```bash
# Follow
docker compose -f stacks/proxy/cloudflared/compose.yml logs -f

# Recent with context
docker compose -f stacks/proxy/cloudflared/compose.yml logs --tail=100

# Check for tunnel errors
docker compose -f stacks/proxy/cloudflared/compose.yml logs 2>&1 | grep -i error
```

## Common Operations

### Update Ingress Rules

```bash
# Edit config.yml
vim stacks/proxy/cloudflared/config.yml

# Restart to apply
docker compose -f stacks/proxy/cloudflared/compose.yml restart
```

### Switch from credentials.json to TUNNEL_TOKEN

```bash
# 1. Edit compose.yml — uncomment the TUNNEL_TOKEN line
# 2. Create .env file (or export in shell)
echo "CLOUDFLARED_TUNNEL_TOKEN=<your-token>" > stacks/proxy/cloudflared/.env

# 3. Restart
docker compose -f stacks/proxy/cloudflared/compose.yml up -d
```

### Access Tunnel Metrics

```bash
# Metrics available on port 2000 (internal only)
curl -s http://cloudflared:2000/metrics

# For Prometheus scraping, add the target to prometheus.yml:
# - targets: ['cloudflared:2000']
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `Tunnel not found` | Invalid credentials | Regenerate tunnel token |
| `Failed to connect to origin` | Traefik not running | `docker compose -f proxy/compose.yml ps` |
| `403 Forbidden` | DNS not proxied (grey cloud) | Enable proxy in CF dashboard |
| `Connection refused` | cloudflared not on proxy network | Verify networks in compose.yml |
| `Websocket handshake failed` | Network issue | Check Cloudflare status page |
| `ERR_SSL_VERSION_OR_CIPHER_MISMATCH` | Traefik config | Check TLS options in Traefik |

## Maintenance

### Update cloudflared

```bash
docker compose -f stacks/proxy/cloudflared/compose.yml pull
docker compose -f stacks/proxy/cloudflared/compose.yml up -d
```

### View Tunnel Information

```bash
cloudflared tunnel info circuithq
cloudflared tunnel list
```

### Route Additional Hostnames

```bash
cloudflared tunnel route dns circuithq <new-subdomain>.YOUR-DOMAIN.com
```

Then add an ingress rule in `config.yml` and restart.

## Rollback

```bash
docker compose -f stacks/proxy/cloudflared/compose.yml down
git checkout HEAD~1 -- stacks/proxy/cloudflared/
docker compose -f stacks/proxy/cloudflared/compose.yml up -d
```