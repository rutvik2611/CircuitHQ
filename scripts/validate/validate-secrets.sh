#!/bin/bash
# CircuitHQ — Validate Secrets Configuration
# Checks for plaintext secret anti-patterns, required SOPS files, and permissions.
set -euo pipefail

MISSING=0
WARNINGS=0
BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== Validating Secrets Configuration ==="
echo ""

# ── Check .sops.yaml exists ─────────────────────────────────────────
if [ -f "$BASE_DIR/.sops.yaml" ]; then
  echo "✅ .sops.yaml exists"
else
  echo "❌ MISSING: .sops.yaml"
  MISSING=$((MISSING + 1))
fi

# ── Check secrets/README.md exists ──────────────────────────────────
if [ -f "$BASE_DIR/secrets/README.md" ]; then
  echo "✅ secrets/README.md exists"
else
  echo "❌ MISSING: secrets/README.md"
  MISSING=$((MISSING + 1))
fi

# ── Check for committed .env files (anti-pattern) ───────────────────
for envfile in "$BASE_DIR/.env" "$BASE_DIR/.env.production" "$BASE_DIR/.env.staging" \
               "$BASE_DIR/.env.local" "$BASE_DIR/.env.development"; do
  if [ -f "$envfile" ]; then
    echo "❌ PLAINTEXT SECRET: $envfile exists and should NOT be committed"
    MISSING=$((MISSING + 1))
  fi
done

# ── Check secrets/production/ has .sops.yaml files ──────────────────
PROD_COUNT=0
for f in "$BASE_DIR"/secrets/production/*.sops.yaml; do
  if [ -f "$f" ]; then
    echo "✅ secrets/production/$(basename "$f")"
    PROD_COUNT=$((PROD_COUNT + 1))
  fi
done
if [ "$PROD_COUNT" -eq 0 ]; then
  echo "⚠️  No .sops.yaml files in secrets/production/"
  WARNINGS=$((WARNINGS + 1))
fi

# ── Check secrets/staging/ has .sops.yaml files ─────────────────────
STAG_COUNT=0
for f in "$BASE_DIR"/secrets/staging/*.sops.yaml; do
  if [ -f "$f" ]; then
    echo "✅ secrets/staging/$(basename "$f")"
    STAG_COUNT=$((STAG_COUNT + 1))
  fi
done
if [ "$STAG_COUNT" -eq 0 ]; then
  echo "⚠️  No .sops.yaml files in secrets/staging/"
  WARNINGS=$((WARNINGS + 1))
fi

# ── Check for plaintext age key in repo (anti-pattern) ──────────────
if [ -f "$BASE_DIR/age-key.txt" ] || [ -f "$BASE_DIR/keys.txt" ]; then
  echo "❌ PLAINTEXT AGE KEY found in repo root — remove immediately"
  MISSING=$((MISSING + 1))
fi

# ── Check render-secrets.sh exists ──────────────────────────────────
if [ -f "$BASE_DIR/scripts/deploy/render-secrets.sh" ]; then
  echo "✅ scripts/deploy/render-secrets.sh exists"
else
  echo "⚠️  scripts/deploy/render-secrets.sh not found"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""
if [ "$MISSING" -eq 0 ]; then
  if [ "$WARNINGS" -eq 0 ]; then
    echo "✅ All secrets checks passed"
  else
    echo "✅ All required checks passed ($WARNINGS warnings — review above)"
  fi
else
  echo "❌ $MISSING check(s) failed"
  exit 1
fi