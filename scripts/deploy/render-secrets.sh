#!/bin/bash
# CircuitHQ — Decrypt SOPS Secrets to Runtime .env Files
# ========================================================
# Scans secrets/ for .sops.yaml files and decrypts them to .env files
# with strict permissions (0600) for consumption by Docker Compose.
#
# Usage:
#   ./scripts/deploy/render-secrets.sh              # all environments
#   ENV=production ./scripts/deploy/render-secrets.sh
#   ENV=staging    ./scripts/deploy/render-secrets.sh
#
# Prerequisites:
#   - sops installed (brew install sops)
#   - age private key at ~/.config/sops/age/keys.txt
#   - .sops.yaml in repo root with matching public key
#
# Security:
#   - Output files get 0600 permissions (owner read/write only)
#   - Output files are .gitignore'd (secrets/**/*.decrypted)
#   - Never commit output files

set -euo pipefail

# Ensure sops can find the age key
AGE_KEY_PATH="$HOME/.config/sops/age/keys.txt"
if [ -f "$AGE_KEY_PATH" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  export SOPS_AGE_KEY_FILE="$AGE_KEY_PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV="${ENV:-all}"  # all, production, staging

# Ensure sops is available
if ! command -v sops &>/dev/null; then
  echo "❌ sops not found. Install: brew install sops"
  exit 1
fi

echo "=== Render Secrets: ENV=$ENV ==="
echo ""

render_dir() {
  local dir="$1"
  local env_name="$2"

  if [ ! -d "$BASE_DIR/secrets/$dir" ]; then
    return
  fi

  mkdir -p "$BASE_DIR/.secrets-rendered/$env_name"

  for sops_file in "$BASE_DIR/secrets/$dir"/*.sops.yaml; do
    if [ ! -f "$sops_file" ]; then
      continue
    fi

    base_name="$(basename "$sops_file" .sops.yaml)"
    output_file="$BASE_DIR/.secrets-rendered/$env_name/$base_name.env"

    echo "▶️  Decrypting $dir/$base_name.sops.yaml -> .secrets-rendered/$env_name/$base_name.env"
    sops --decrypt "$sops_file" > "$output_file"
    chmod 0600 "$output_file"
    echo "   ✅ $output_file (0600)"

    # For Authelia, split secrets into individual files (one per secret).
    # Authelia reads *_FILE env vars as a single value per file.
    if [ "$base_name" = "authelia" ]; then
      local split_dir="$BASE_DIR/.secrets-rendered/$env_name/authelia"
      mkdir -p "$split_dir"
      # Parse YAML "key: value" (key may contain underscores, value on same line)
      while IFS= read -r line; do
        # Only handle top-level "key: value" lines (no leading spaces)
        if [[ "$line" =~ ^([a-z_]+):[[:space:]]*(.*)$ ]]; then
          local key="${BASH_REMATCH[1]}"
          local val="${BASH_REMATCH[2]}"
          # Strip YAML quotes
          val="${val%\"}"; val="${val#\"}"
          if [ -n "${val:-}" ]; then
            printf '%s' "$val" > "$split_dir/$key"
            chmod 0600 "$split_dir/$key"
            echo "   ➜ split: $split_dir/$key"
          fi
        fi
      done < "$output_file"
      rm -f "$output_file"
      echo "   ✅ Authelia secrets split into $split_dir/"
    fi

    # For cloudflared, convert to docker-compose env_file format (KEY=VALUE)
    # so cloudflared's compose can read CLOUDFLARED_TUNNEL_TOKEN directly.
    if [ "$base_name" = "cloudflare" ]; then
      local cf_env="$BASE_DIR/.secrets-rendered/$env_name/cloudflare.env.docker"
      rm -f "$cf_env"
      while IFS= read -r line; do
        if [[ "$line" =~ ^([a-z_]+):[[:space:]]*(.*)$ ]]; then
          local key="${BASH_REMATCH[1]}"
          local val="${BASH_REMATCH[2]}"
          val="${val%\"}"; val="${val#\"}"
          if [ -n "${val:-}" ]; then
            case "$key" in
              tunnel_token) printf 'TUNNEL_TOKEN=%s\n' "$val" >> "$cf_env" ;;
              api_token)    printf 'CLOUDFLARE_API_TOKEN=%s\n' "$val" >> "$cf_env" ;;
            esac
          fi
        fi
      done < "$output_file"
      chmod 0600 "$cf_env"
      echo "   ✅ cloudflared env ready: $cf_env"
    fi
  done
}

if [ "$ENV" = "production" ] || [ "$ENV" = "all" ]; then
  render_dir "production" "production"
fi

if [ "$ENV" = "staging" ] || [ "$ENV" = "all" ]; then
  render_dir "staging" "staging"
fi

echo ""
echo "✅ Secrets rendered to .secrets-rendered/"
echo "   Reference these files in Docker Compose with:"
echo '   env_file: .secrets-rendered/<env>/<service>.env'