# Example Public App — whoami

A minimal public-facing service for testing the CircuitHQ ingress pipeline.

## Service

- **Image:** `traefik/whoami:v1.10`
- **Container:** `circuithq-whoami`
- **Port:** 80 (internal)

## URL

```
https://whoami.circuithq.internal
```

Returns request metadata (headers, IP, method, URI).

## Networks

| Network | Purpose |
|---------|---------|
| `circuithq-proxy` | Traefik routing — enables public ingress |
| `circuithq-shared` | Optional communication with other services |

## Exposure

- **Public:** ✅ Yes (via Traefik)
- **Middlewares:** `public-chain@file` (security headers + rate limiting)
- **Auth:** None by default. Change to `auth-chain@file` for Authelia protection.

## Health Check

```bash
# Direct container health
docker inspect --format '{{.State.Health.Status}}' circuithq-whoami

# Via Traefik
curl -s https://whoami.circuithq.internal
```

## Backup

This is a stateless demo service — no persistent data. For stateful apps, add a docker volume and include it in the backup script.

## Rollback

```bash
# Restore previous compose.yml
git checkout HEAD~1 -- stacks/apps/example-public-app/compose.yml
docker compose -f stacks/apps/example-public-app/compose.yml up -d
```

## Security Notes

- `exposedByDefault: false` ensures this service **only** routes because of the explicit `traefik.enable=true` label
- Add `auth-chain@file` middleware for Authelia authentication
- For production, replace with an actual application compose.yml
- Review [Traefik routing docs](../../docs/architecture/traefik.md) for advanced configuration