# Secrets

This directory contains SOPS-encrypted secret files. Never commit plaintext secrets.

## Structure

```
secrets/
  production/
    cloudflare.sops.yaml   # Cloudflare tunnel token, API tokens
    traefik.sops.yaml       # ACME email, dashboard users
    authelia.sops.yaml      # User passwords, JWT secret, encryption key
    grafana.sops.yaml       # Admin password
    restic.sops.yaml        # Restic repository password
  staging/
    example.sops.yaml       # Example template
```

## Key Custody

- The age private key lives at `~/.config/sops/age/keys.txt` (0600 permissions)
- Back up the age key offline (USB drive, printed copy kept secure)
- Use separate keys for production and staging
- No plaintext `.env` files are committed to Git

## Decryption Flow

1. On the deploy target, the age key is present at the standard path
2. `scripts/deploy/render-secrets.sh` decrypts SOPS files into runtime `.env` files
3. Runtime files are created with `0600` permissions
4. Docker Compose references the runtime files

## Rotation

- Rotate tokens periodically (every 90 days recommended for Cloudflare, GitHub, etc.)
- Update SOPS-encrypted files in place
- Keep the previous secret available during rotation to avoid downtime
- Update .sops.yaml if age keys change

## Anti-patterns

- Do not commit `.env.production` to Git — ever
- Do not paste secrets into CI logs, issue comments, or chat
- Do not mount the whole `secrets/` folder into containers
- Do not reuse Cloudflare global API keys — use scoped tokens
- Do not store the restic password only on the machine being backed up