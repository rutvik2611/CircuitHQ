# Traefik Runbook

## Prerequisites

- Docker and Docker Compose installed
- Networks exist: `circuithq-proxy`, `circuithq-monitoring`, `circuithq-security`
- Volume exists: `circuithq-traefik-acme`
- DNS records point to the host (or local hosts file for testing)

## Deploy

```bash
# Create prerequisite resources if not already present
docker network create circuithq-proxy --attachable --driver overlay 2>/dev/null || \
  docker network create circuithq-proxy --attachable

docker network create circuithq-monitoring --internal --attachable
docker network create circuithq-security --internal --attachable

docker volume create circuithq-traefik-acme

# Deploy Traefik
cd stacks/proxy
docker compose up -d

# Verify
docker compose ps
docker compose logs --tail=50
```

## Health Check

```bash
# Traefik ping (internal)
docker exec circuithq-traefik traefik healthcheck --ping

# Dashboard
curl -k https://traefik.circuithq.internal/dashboard/

# Metrics
curl -s http://localhost:8080/metrics | head -20
```

## Logs

```bash
# Follow all logs
docker compose -f stacks/proxy/compose.yml logs -f

# Recent logs (JSON format for log aggregators)
docker compose -f stacks/proxy/compose.yml logs --tail=100
```

## Common Operations

### Add a New Service Behind Traefik

Add these Docker labels to the service's compose.yml:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<name>.rule=Host(`app.example.com`)"
  - "traefik.http.routers.<name>.entrypoints=websecure"
  - "traefik.http.routers.<name>.tls=true"
  - "traefik.http.routers.<name>.tls.certresolver=letsencrypt"
  - "traefik.http.services.<name>.loadbalancer.server.port=8080"
```

Enable public security middleware:

```yaml
  - "traefik.http.routers.<name>.middlewares=public-chain@file"
```

Enable Authelia auth (after Phase 7):

```yaml
  - "traefik.http.routers.<name>.middlewares=auth-chain@file"
```

### Renew Certificates

Let's Encrypt certificates auto-renew. To force renewal:

```bash
docker exec circuithq-traefik traefik renew --certificates
docker restart circuithq-traefik
```

Alternatively, delete the ACME storage and restart:

```bash
docker compose -f stacks/proxy/compose.yml down
docker volume rm circuithq-traefik-acme
docker volume create circuithq-traefik-acme
docker compose -f stacks/proxy/compose.yml up -d
```

### Switch to Let's Encrypt Staging

Edit `stacks/proxy/traefik/static.yml`:

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"
```

Then restart:

```bash
docker compose -f stacks/proxy/compose.yml restart
```

### View Dashboard

```bash
# Via Tailscale (preferred)
open http://traefik.circuithq.internal/dashboard/
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `404 page not found` | Route rule mismatch | Check `traefik.http.routers.<name>.rule` label |
| `Gateway Timeout` | Service not on proxy network | Add `circuithq-proxy` network to service |
| Certificate errors | ACME rate limit / DNS | Check `docker compose logs traefik` for ACME errors |
| Dashboard inaccessible | IP not in whitelist | Connect via Tailscale or add IP to `dashboard-auth` |
| `exposedByDefault` warning | Container missing labels | Add `traefik.enable=true` or ignore if intentional |
| Prometheus no data | Metrics endpoint unreachable | Verify `circuithq-monitoring` network connection |

## Security Notes

- **Do not expose port 8080** (dashboard/metrics) to the public internet
- **Do not set `exposedByDefault: true`** — this is the most common Traefik misconfiguration
- **Rotate ACME email** before going to production (`admin@circuithq.internal` is a placeholder)
- **Production readiness checklist:**
  - [ ] Replace ACME email placeholder
  - [ ] Test with Let's Encrypt staging first
  - [ ] Verify dashboard is not internet-accessible
  - [ ] Configure Cloudflare Tunnel (Phase 5) for public ingress
  - [ ] Deploy Authelia (Phase 7) for auth-chain middleware

## Rollback

```bash
# Stop and remove Traefik
cd stacks/proxy
docker compose down

# Remove ACME data (certs will be re-issued)
docker volume rm circuithq-traefik-acme

# Re-deploy previous version
git checkout <previous-commit>
docker compose up -d
```