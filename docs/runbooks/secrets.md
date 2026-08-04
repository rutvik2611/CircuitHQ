# Secrets Management Runbook

## Overview

CircuitHQ uses **SOPS (Secrets OPerationS)** with **age** encryption to manage secrets in Git. Encrypted `.sops.yaml` files are committed; plaintext secrets are **never** committed.

```
                 ┌──────────────────────┐
                 │  .sops.yaml (config)  │
                 │  age public key       │
                 └─────────┬────────────┘
                           │
              ┌────────────┴────────────┐
              │  secrets/production/     │
              │  cloudflare.sops.yaml    │  ← encrypted
              │  traefik.sops.yaml       │  ← encrypted
              └────────────┬────────────┘
                           │ sops --decrypt
                           ▼
              ┌─────────────────────────┐
              │  .secrets-rendered/      │
              │  production/env files    │  ← 0600, .gitignore'd
              └─────────────────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │  Docker Compose          │
              │  env_file references     │
              └─────────────────────────┘
```

## Prerequisites

```bash
# Install SOPS
brew install sops

# Install age (usually installed with SOPS as a dependency)
brew install age

# Generate age key (if not already done)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

## Key Custody

### Age Key Location

- **Private key:** `~/.config/sops/age/keys.txt` (0600 permissions)
- **Public key:** The `age1...` line in keys.txt (safe to share)

### Key Backup

The age private key is the **master key** to all secrets. Loss means all encrypted data is unrecoverable.

```bash
# Backup to secure offline storage
cp ~/.config/sops/age/keys.txt /Volumes/EncryptedUSB/backup/age-key.txt
# Or print to paper and store in a safe
```

### Key Rotation

1. Generate a new key pair
2. Update `.sops.yaml` with the new public key
3. Re-encrypt all `.sops.yaml` files: `sops updatekeys -y secrets/**/*.sops.yaml`
4. Deploy the new private key to all targets

## Setup (First Time)

### Step 1: Generate age key

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
cat ~/.config/sops/age/keys.txt | grep "public key"
# Output: # public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Step 2: Update .sops.yaml

Edit `.sops.yaml` in the repo root. Replace `AGE_PLACEHOLDER_AGE_PUBLIC_KEY` with your actual age public key.

### Step 3: Encrypt a secret file

```bash
# Create a file with plaintext secrets (temporary)
cat > /tmp/cloudflare-secrets.yaml << 'EOF'
tunnel_token: "eyJhbGciOiJIUzI1NiIs..."
api_token: "abcdef1234567890..."
EOF

# Encrypt it with SOPS
sops --encrypt --output secrets/production/cloudflare.sops.yaml /tmp/cloudflare-secrets.yaml

# The temp file can now be deleted
rm /tmp/cloudflare-secrets.yaml
```

### Step 4: Verify encryption

```bash
# View encrypted file (decrypts in-memory)
sops secrets/production/cloudflare.sops.yaml
```

### Step 5: Decrypt for runtime

```bash
# Render all secrets to runtime env files
./scripts/deploy/render-secrets.sh
```

## Daily Operations

### View a secret

```bash
sops secrets/production/cloudflare.sops.yaml
```

### Edit a secret (in-place with $EDITOR)

```bash
sops secrets/production/cloudflare.sops.yaml
```

### Add a new secret file

```bash
# Create plaintext source
cat > /tmp/new-secret.yaml << 'EOF'
password: "super-secret-password"
EOF

# Encrypt
sops --encrypt --output secrets/production/new-service.sops.yaml /tmp/new-secret.yaml

# Clean up
rm /tmp/new-secret.yaml
```

### Re-encrypt all secrets (after key rotation)

```bash
sops updatekeys -y secrets/**/*.sops.yaml
```

## Security Rules

| Rule | Why |
|------|-----|
| Never commit `keys.txt` | It's the master key to all secrets |
| Never commit `.env` files | Plaintext secrets in Git |
| Never paste secrets in chat/CI logs | Log persistence = exposure |
| `chmod 600` all rendered env files | Prevent other users/mounts from reading |
| Rotate Cloudflare tokens every 90 days | Standard security hygiene |
| Keep previous secret during rotation | Avoid downtime from stale secrets |
| Don't mount entire `secrets/` folder | Containers only need their specific .env |

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `Error: could not find an age key` | keys.txt not at expected path | `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt` |
| `Error: age key not matching` | Wrong public key in .sops.yaml | Run `sops updatekeys -y` or fix public key mismatch |
| `bash: sops: command not found` | sops not installed | `brew install sops` |
| `Permission denied (publickey)` | Wrong key file permissions | `chmod 600 ~/.config/sops/age/keys.txt` |
| Decrypted file is empty | SOPS file was never encrypted | Run `sops --encrypt` on the file |

## Rollback

```bash
# Restore previous version of a secret
git checkout HEAD~1 -- secrets/production/cloudflare.sops.yaml

# Re-render
./scripts/deploy/render-secrets.sh
```