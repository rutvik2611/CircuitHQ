#!/bin/bash
# CircuitHQ — Set Cloudflare Tunnel Token
# ==========================================
# Prompts for your Cloudflare tunnel token (hidden input) and stores it so
# cloudflared can start. Writes to the gitignored rendered env file and
# best-efforts encrypting it into the SOPS secret.
#
# Usage: bash scripts/set-cloudflare-token.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure sops can find the age key
AGE_KEY_PATH="$HOME/.config/sops/age/keys.txt"
if [ -f "$AGE_KEY_PATH" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  export SOPS_AGE_KEY_FILE="$AGE_KEY_PATH"
fi

echo "=== CircuitHQ — Set Cloudflare Tunnel Token ==="
echo ""

# Read token without echoing
read -s -rp "Paste Cloudflare tunnel token (hidden): " TOKEN
echo ""

if [ -z "$TOKEN" ]; then
  echo "❌ No token provided — aborting."
  exit 1
fi

# 1. Write to gitignored rendered docker env file (guaranteed way cloudflared reads it)
RENDERED_DIR="$BASE_DIR/.secrets-rendered/production"
mkdir -p "$RENDERED_DIR"
printf 'CLOUDFLARED_TUNNEL_TOKEN=%s\n' "$TOKEN" > "$RENDERED_DIR/cloudflare.env.docker"
chmod 0600 "$RENDERED_DIR/cloudflare.env.docker"
echo "✅ Token written to $RENDERED_DIR/cloudflare.env.docker (0600)"

# 2. Best-effort: also persist in the SOPS-encrypted secret
CLOUDFLARE_SOPS="$BASE_DIR/secrets/production/cloudflare.sops.yaml"
if [ -f "$CLOUDFLARE_SOPS" ] && command -v sops &>/dev/null; then
  if sops --set '["tunnel_token"]' "\"$TOKEN\"" "$CLOUDFLARE_SOPS" 2>/dev/null; then
    echo "✅ Also stored in SOPS secret: ${CLOUDFLARE_SOPS#$BASE_DIR/}"
  else
    echo "⚠️  SOPS update skipped — token is in rendered file (still works, but won't survive a re-render)"
  fi
fi

echo ""
echo "Done. Now start cloudflared:"
echo "  docker compose -f stacks/proxy/cloudflared/compose.yml up -d"