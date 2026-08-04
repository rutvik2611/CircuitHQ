#!/bin/bash
# CircuitHQ — Validate Cloudflare Tunnel (cloudflared) Config
# Checks that required config files exist and have expected structure
set -euo pipefail

MISSING=0
BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CLOUDFLARED_DIR="$BASE_DIR/stacks/proxy/cloudflared"

echo "=== Validating Cloudflare Tunnel Configuration ==="
echo ""

# Check compose.yml exists
if [ -f "$CLOUDFLARED_DIR/compose.yml" ]; then
  echo "✅ cloudflared/compose.yml exists"
else
  echo "❌ MISSING: cloudflared/compose.yml"
  MISSING=$((MISSING + 1))
fi

# Check config template exists
if [ -f "$CLOUDFLARED_DIR/config.yml.template" ]; then
  echo "✅ cloudflared/config.yml.template exists"
else
  echo "❌ MISSING: cloudflared/config.yml.template"
  MISSING=$((MISSING + 1))
fi

# Check config.yml exists (the active config)
if [ -f "$CLOUDFLARED_DIR/config.yml" ]; then
  echo "✅ cloudflared/config.yml exists"
else
  echo "⚠️  cloudflared/config.yml not found (deploy config not yet created)"
fi

# Warn if credentials.json is present (should not be committed)
if [ -f "$CLOUDFLARED_DIR/credentials.json" ]; then
  echo "⚠️  WARNING: credentials.json found — verify it's in .gitignore"
else
  echo "✅ cloudflared/credentials.json absent (expected — not committed)"
fi

# Validate YAML syntax of config files
if command -v python3 &>/dev/null; then
  for f in "compose.yml" "config.yml.template"; do
    file="$CLOUDFLARED_DIR/$f"
    if [ -f "$file" ]; then
      if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        echo "✅ YAML syntax: $f"
      else
        echo "❌ YAML syntax error: $f"
        MISSING=$((MISSING + 1))
      fi
    fi
  done
fi

# Check infra/cloudflare/README.md exists
if [ -f "$BASE_DIR/infra/cloudflare/README.md" ]; then
  echo "✅ infra/cloudflare/README.md exists"
else
  echo "❌ MISSING: infra/cloudflare/README.md"
  MISSING=$((MISSING + 1))
fi

echo ""
if [ "$MISSING" -eq 0 ]; then
  echo "✅ All Cloudflare Tunnel config checks passed"
else
  echo "❌ $MISSING check(s) failed"
  exit 1
fi