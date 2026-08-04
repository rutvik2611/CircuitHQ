# Example Private App — nginx (unexposed)

A minimal private service demonstrating the default security posture: **no accidental public exposure**.

## Service

- **Image:** `nginx:alpine-slim`
- **Container:** `circuithq-example-private`
- **Port:** 80 (internal only)
- **User:** `101:101` (non-root)

## URL

**No external URL.** This service is not routed by Traefik.

## Networks

| Network | Purpose |
|---------|---------|
| `circuithq-private` | Internal network (marked `internal: true`) — no external route |

## Exposure

- **Public:** ❌ No
- **Traefik labels:** None — `traefik.enable` is not set, so `exposedByDefault: false` keeps it hidden
- **Access:** Only other services on the `circuithq-private` network can reach it

## Health Check

```bash
# Direct container health
docker inspect --format '{{.State.Health.Status}}' circuithq-example-private

# From another container on the private network
docker run --rm --network circuithq-private alpine wget -q -O- http://circuithq-example-private
```

## Backup

Stateless demo — no persistent data.

## Rollback

```bash
git checkout HEAD~1 -- stacks/apps/example-private-app/compose.yml
docker compose -f stacks/apps/example-private-app/compose.yml up -d
```

## Security Notes

- No `traefik.enable=true` label → not visible to Traefik
- `circuithq-private` is `internal: true` → no host-level external route
- Runs as non-root user (`nginx` UID 101)
- For a production private app, review if `circuithq-shared` or `circuithq-security` network access is needed