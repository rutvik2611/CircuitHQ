# Authelia Runbook

## Prerequisites

- Docker and Docker Compose installed
- Networks exist: `circuithq-proxy`, `circuithq-security`
- Volume exists: `circuithq-redis-data`
- Traefik stack is running (Phase 4)
- SOPS + age key configured (Phase 6)

## Deploy

```bash
# 1. Create prerequisite resources (if not already present)
docker network create circuithq-security --internal --attachable 2>/dev/null || true
docker volume create circuithq-redis-data 2>/dev/null || true

# 2. Decrypt secrets
sops --decrypt secrets/production/authelia.sops.yaml > /tmp/authelia.env
chmod 0600 /tmp/authelia.env

# 3. Generate admin password hash
docker run authelia/authelia:4.38 authelia hash-password 'your-admin-password'
# Copy the output hash into users_database.yml

# 4. Start Authelia stack
cd stacks/auth
AUTHELIA_SECRETS=$(cat /tmp/authelia.env) docker compose up -d

# 5. Verify
docker compose ps
docker compose logs --tail=20
```

## Health Check

```bash
# Container health
docker ps --filter name=circuithq-authelia --format "{{.Status}}"
docker ps --filter name=circuithq-authelia-redis --format "{{.Status}}"

# Authelia health endpoint
curl -s http://localhost:9091/api/health | python3 -m json.tool

# Check forward-auth endpoint (should 401 without cookie)
curl -s -o /dev/null -w "%{http_code}" http://authelia:9091/api/authz/forward-auth
```

## Add a New User

### Step 1: Generate password hash

```bash
docker run authelia/authelia:4.38 authelia hash-password 'new-user-password'
# Output: $argon2id$v=19$m=65536,t=3,p=4$...
```

### Step 2: Add user to database

Edit `stacks/auth/authelia/users_database.yml`:

```yaml
newuser:
  disabled: false
  displayname: "New User"
  password: "$argon2id$v=19$m=65536,t=3,p=4$..."
  email: newuser@example.com
  groups:
    - users
```

### Step 3: Restart Authelia

```bash
docker compose -f stacks/auth/compose.yml restart authelia
```

## Reset a User's Password

### Option 1: Admin resets in the database

```bash
# Generate new hash
docker run authelia/authelia:4.38 authelia hash-password 'new-temp-password'
# Edit user entry in users_database.yml with new hash
docker compose -f stacks/auth/compose.yml restart authelia
```

### Option 2: User self-service (requires SMTP configured)

1. Go to `https://auth.circuithq.internal`
2. Click "Forgot password?"
3. Check email for reset link
4. Follow link to set new password

## Account Recovery

### User locked out (after 5 failed attempts)

The regulation policy bans the IP for 5 minutes after 5 failed attempts within 2 minutes. To immediately unban:

```bash
# Restart Authelia (clears in-memory ban state)
docker compose -f stacks/auth/compose.yml restart authelia

# Or wait for the ban timeout (5 minutes)
```

### User lost TOTP device

1. As admin, edit the user's entry in `users_database.yml`
2. Remove or reset the `totp` field
3. The user will be prompted to re-enroll TOTP on next login
4. Send them the enrollment QR code

### Forgot admin password entirely

If no admin can log in:

```bash
# 1. Stop Authelia
docker compose -f stacks/auth/compose.yml down

# 2. Edit users_database.yml — change admin password hash
#    (generate new hash)
docker run authelia/authelia:4.38 authelia hash-password 'new-admin-password'
# Paste the hash into users_database.yml

# 3. Restart
docker compose -f stacks/auth/compose.yml up -d
```

## Common Operations

### Apply Configuration Changes

```bash
# After editing any config file in stacks/auth/authelia/
docker compose -f stacks/auth/compose.yml restart authelia
```

### Rotate Authelia Secrets

```bash
# 1. Generate new secrets
openssl rand -base64 64 > /tmp/jwt_secret      # JWT secret
openssl rand -base64 64 > /tmp/session_secret   # Session secret
openssl rand -hex 32 > /tmp/storage_key         # Storage encryption key

# 2. Update SOPS file
sops secrets/production/authelia.sops.yaml
# Replace values with new ones

# 3. Re-encrypt
sops --encrypt --in-place secrets/production/authelia.sops.yaml

# 4. Re-deploy with new secrets
sops --decrypt secrets/production/authelia.sops.yaml > /tmp/authelia.env
docker compose -f stacks/auth/compose.yml up -d
```

### View Active Sessions

```bash
# Connect to Redis
docker exec -it circuithq-authelia-redis redis-cli

# List keys
KEYS authelia:*
# Get session info
GET <session-key>
```

## Traefik Integration

The forward-auth middleware is defined in `stacks/proxy/traefik/dynamic/middlewares.yml`:

```yaml
auth-chain:
  chain:
    middlewares:
      - secHeaders
      - rateLimit
      - auth-forward          # ← Enabled during Phase 7
```

To protect a new service, add the middleware to the router's labels:

```yaml
labels:
  - "traefik.http.routers.<name>.middlewares=auth-chain@file"
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `401 Unauthorized` on all routes | Authelia not reachable from Traefik | Verify both on `circuithq-proxy` network |
| `502 Bad Gateway` from Traefik | Authelia container not running | `docker compose -f stacks/auth/compose.yml ps` |
| Endless login redirect | Session cookie domain mismatch | Check `session.domain` in configuration.yml |
| `Invalid password` | User not in database | Check users_database.yml entry |
| TOTP QR not appearing | Authelia storage issue | Check `docker compose logs authelia` for DB errors |
| Redis connection refused | Redis not healthy | `docker compose -f stacks/auth/compose.yml logs redis` |
| Forward-auth timeout | Network latency or misconfig | Check `auth-forward` address in middlewares.yml |
| MFA not enforced | Policy set to `one_factor` | Change to `two_factor` in access_rules.yml |

## Rollback

```bash
# Stop Authelia
docker compose -f stacks/auth/compose.yml down

# Restore previous config version
git checkout HEAD~1 -- stacks/auth/
git checkout HEAD~1 -- secrets/production/authelia.sops.yaml

# Re-deploy
docker compose -f stacks/auth/compose.yml up -d
```