#!/bin/bash
# CircuitHQ — Pre-Deployment Setup
# ===================================
# Interactive one-time setup script for first-time deployment on a new host.
# Walks through: prerequisites, SOPS, age keys, Docker infra, secrets,
# config placeholders, and validation.
#
# Idempotent — safe to re-run. Skips already-completed steps.
#
# Usage:
#   bash scripts/setup.sh                    # Full interactive setup
#   bash scripts/setup.sh --dry-run          # Show what would be done
#   bash scripts/setup.sh --quick            # Auto-confirm all safe steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=false
QUICK=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --quick)   QUICK=true ;;
  esac
done

confirm() {
  local prompt="$1"
  if [ "$QUICK" = true ]; then
    echo -e "  ${YELLOW}→${NC} $prompt [auto-yes]"
    return 0
  fi
  read -rp "$(echo -e "  ${CYAN}?${NC} $prompt [y/N] ")" REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

step_header() {
  echo ""
  echo -e "${CYAN}══════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════${NC}"
}

echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     CircuitHQ Pre-Deployment Setup            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo "Repo: $BASE_DIR"
echo ""

# ────────────────────────────────────────────────────────────────────
step_header "Step 1: Docker Runtime"
# ────────────────────────────────────────────────────────────────────
if docker info &>/dev/null; then
  echo -e "  ${GREEN}✅${NC} Docker running — $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
else
  echo -e "  ${RED}❌${NC} Docker not running"
  echo "     Start OrbStack / Docker Desktop / Colima, then re-run."
  echo "     See: scripts/bootstrap/01-install-docker.sh"
  exit 1
fi

if docker compose version &>/dev/null; then
  echo -e "  ${GREEN}✅${NC} Docker Compose available"
else
  echo -e "  ${RED}❌${NC} Docker Compose not found"
  exit 1
fi

# ────────────────────────────────────────────────────────────────────
step_header "Step 2: SOPS + Age Key"
# ────────────────────────────────────────────────────────────────────
SOPS_INSTALLED=false
if command -v sops &>/dev/null; then
  echo -e "  ${GREEN}✅${NC} SOPS installed: $(sops --version 2>&1 | head -1)"
  SOPS_INSTALLED=true
else
  echo -e "  ${YELLOW}⚠️${NC} SOPS not installed"
  if confirm "Install SOPS via Homebrew?"; then
    if [ "$DRY_RUN" = false ]; then
      brew install sops
      echo -e "  ${GREEN}✅${NC} SOPS installed"
      SOPS_INSTALLED=true
    else
      echo -e "  ${YELLOW}  (dry-run: would install sops)${NC}"
    fi
  else
    echo -e "  ${YELLOW}  Skipping SOPS install — deploy will fail without it${NC}"
  fi
fi

AGE_KEY_PATH="$HOME/.config/sops/age/keys.txt"
AGE_KEY_EXISTS=false
AGE_PUBLIC_KEY=""

if [ -f "$AGE_KEY_PATH" ]; then
  PERMS=$(stat -f "%Lp" "$AGE_KEY_PATH" 2>/dev/null || stat -c "%a" "$AGE_KEY_PATH" 2>/dev/null)
  echo -e "  ${GREEN}✅${NC} Age key found at $AGE_KEY_PATH ($PERMS)"
  AGE_KEY_EXISTS=true
  AGE_PUBLIC_KEY=$(grep -o 'age1[a-z0-9]\{50,\}' "$AGE_KEY_PATH" 2>/dev/null || true)
else
  echo -e "  ${YELLOW}⚠️${NC} Age key not found at $AGE_KEY_PATH"
  if confirm "Generate a new age key pair?"; then
    if [ "$DRY_RUN" = false ]; then
      mkdir -p "$(dirname "$AGE_KEY_PATH")"
      age-keygen -o "$AGE_KEY_PATH" 2>&1
      chmod 600 "$AGE_KEY_PATH"
      echo -e "  ${GREEN}✅${NC} Age key generated at $AGE_KEY_PATH"
      AGE_KEY_EXISTS=true
      AGE_PUBLIC_KEY=$(grep -o 'age1[a-z0-9]\{50,\}' "$AGE_KEY_PATH" 2>/dev/null || true)
      echo -e "  ${GREEN}✅${NC} Public key: $AGE_PUBLIC_KEY"
    else
      echo -e "  ${YELLOW}  (dry-run: would generate age key)${NC}"
    fi
  fi
fi

# ────────────────────────────────────────────────────────────────────
step_header "Step 3: .sops.yaml — Public Key"
# ────────────────────────────────────────────────────────────────────
SOPS_CONFIG="$BASE_DIR/.sops.yaml"
if [ -n "$AGE_PUBLIC_KEY" ] && grep -q "AGE_PLACEHOLDER_AGE_PUBLIC_KEY" "$SOPS_CONFIG" 2>/dev/null; then
  echo -e "  ${YELLOW}⚠️${NC} .sops.yaml still has placeholder age key"
  echo -e "  Your public key: ${CYAN}$AGE_PUBLIC_KEY${NC}"
  if confirm "Update .sops.yaml with your age public key?"; then
    if [ "$DRY_RUN" = false ]; then
      # Use sed to replace placeholder on both lines
      sed -i '' "s/AGE_PLACEHOLDER_AGE_PUBLIC_KEY/$AGE_PUBLIC_KEY/g" "$SOPS_CONFIG"
      echo -e "  ${GREEN}✅${NC} .sops.yaml updated"
    else
      echo -e "  ${YELLOW}  (dry-run: would update .sops.yaml)${NC}"
    fi
  fi
elif [ -n "$AGE_PUBLIC_KEY" ]; then
  echo -e "  ${GREEN}✅${NC} .sops.yaml appears configured already"
else
  echo -e "  ${YELLOW}⚠️${NC} No age public key available — skip .sops.yaml update"
fi

# ────────────────────────────────────────────────────────────────────
step_header "Step 4: Docker Networks"
# ────────────────────────────────────────────────────────────────────
NETWORK_COUNT=$(docker network ls --filter label=circuithq.network=true --format '{{.Name}}' 2>/dev/null | wc -l | tr -d ' ')
if [ "$NETWORK_COUNT" -ge 9 ]; then
  echo -e "  ${GREEN}✅${NC} All 9 Docker networks exist"
else
  echo -e "  ${YELLOW}⚠️${NC} Found $NETWORK_COUNT of 9 networks"
  if confirm "Create missing Docker networks?"; then
    if [ "$DRY_RUN" = false ]; then
      bash "$BASE_DIR/scripts/bootstrap/02-create-networks.sh"
      echo -e "  ${GREEN}✅${NC} Networks created"
    else
      echo -e "  ${YELLOW}  (dry-run: would run 02-create-networks.sh)${NC}"
    fi
  fi
fi

# ────────────────────────────────────────────────────────────────────
step_header "Step 5: Docker Volumes"
# ────────────────────────────────────────────────────────────────────
VOLUMES=(
  "circuithq-traefik-acme"
  "circuithq-redis-data"
  "circuithq-prometheus-data"
  "circuithq-grafana-data"
  "circuithq-loki-data"
  "circuithq-uptime-kuma-data"
)
MISSING_VOLS=()
for vol in "${VOLUMES[@]}"; do
  if ! docker volume inspect "$vol" &>/dev/null 2>&1; then
    MISSING_VOLS+=("$vol")
  fi
done

if [ ${#MISSING_VOLS[@]} -eq 0 ]; then
  echo -e "  ${GREEN}✅${NC} All 6 Docker volumes exist"
else
  echo -e "  ${YELLOW}⚠️${NC} ${#MISSING_VOLS[@]} volumes missing: ${MISSING_VOLS[*]}"
  if confirm "Create missing Docker volumes?"; then
    if [ "$DRY_RUN" = false ]; then
      for vol in "${MISSING_VOLS[@]}"; do
        docker volume create "$vol"
        echo -e "  ${GREEN}✅${NC} Created volume: $vol"
      done
    else
      echo -e "  ${YELLOW}  (dry-run: would create ${#MISSING_VOLS[@]} volumes)${NC}"
    fi
  fi
fi

# ────────────────────────────────────────────────────────────────────
step_header "Step 6: Config Placeholders"
# ────────────────────────────────────────────────────────────────────

# 6a — Traefik ACME email
TRAEFIK_STATIC="$BASE_DIR/stacks/proxy/traefik/static.yml"
if grep -q "admin@circuithq.internal" "$TRAEFIK_STATIC" 2>/dev/null; then
  echo -e "  ${YELLOW}⚠️${NC} Traefik ACME email is placeholder: admin@circuithq.internal"
  if confirm "Set your ACME email address for Let's Encrypt?"; then
    read -rp "  Enter email: " ACME_EMAIL
    if [ "$DRY_RUN" = false ] && [ -n "$ACME_EMAIL" ]; then
      sed -i '' "s/admin@circuithq.internal/$ACME_EMAIL/g" "$TRAEFIK_STATIC"
      echo -e "  ${GREEN}✅${NC} Traefik ACME email updated to $ACME_EMAIL"
    elif [ -z "$ACME_EMAIL" ]; then
      echo -e "  ${YELLOW}  Skipped (empty input)${NC}"
    fi
  fi
else
  echo -e "  ${GREEN}✅${NC} Traefik ACME email configured"
fi

# 6b — Authelia domain
AUTHELIA_CONFIG="$BASE_DIR/stacks/auth/authelia/configuration.yml"
if grep -q "TODO: replace with your domain" "$AUTHELIA_CONFIG" 2>/dev/null; then
  echo -e "  ${YELLOW}⚠️${NC} Authelia domain is placeholder (circuithq.internal)"
  if confirm "Set your root domain for Authelia?"; then
    read -rp "  Enter domain (e.g. cirquithq.internal): " AUTHELIA_DOMAIN
    if [ "$DRY_RUN" = false ] && [ -n "$AUTHELIA_DOMAIN" ]; then
      sed -i '' "s/circuithq.internal/$AUTHELIA_DOMAIN/g" "$AUTHELIA_CONFIG"
      echo -e "  ${GREEN}✅${NC} Authelia domain updated to $AUTHELIA_DOMAIN"
    elif [ -z "$AUTHELIA_DOMAIN" ]; then
      echo -e "  ${YELLOW}  Skipped (empty input)${NC}"
    fi
  fi
else
  echo -e "  ${GREEN}✅${NC} Authelia domain configured"
fi

# 6c — Approval gate placeholders
APPROVAL_GATE="$BASE_DIR/docs/approvals/laptop-cicd-retarget-approved.md"
if grep -q "\[\[User" "$APPROVAL_GATE" 2>/dev/null; then
  echo -e "  ${YELLOW}⚠️${NC} Approval gate has placeholder name(s)"
  if confirm "Set your name in the approval gate document?"; then
    read -rp "  Enter your name: " USER_NAME
    if [ "$DRY_RUN" = false ] && [ -n "$USER_NAME" ]; then
      sed -i '' "s/\[\[User.*\]\]/$USER_NAME/g" "$APPROVAL_GATE"
      # Also update the Git SHA
      GIT_SHA=$(git -C "$BASE_DIR" rev-parse --short HEAD 2>/dev/null || echo "current")
      sed -i '' "s/\[\[current commit short SHA\]\]/$GIT_SHA/g" "$APPROVAL_GATE"
      echo -e "  ${GREEN}✅${NC} Approval gate updated"
    fi
  fi
else
  echo -e "  ${GREEN}✅${NC} Approval gate placeholders resolved"
fi

# ────────────────────────────────────────────────────────────────────
step_header "Step 7: Render Secrets"
# ────────────────────────────────────────────────────────────────────
if [ "$SOPS_INSTALLED" = true ] && [ -f "$AGE_KEY_PATH" ]; then
  if [ -d "$BASE_DIR/.secrets-rendered" ] && [ "$(ls -A "$BASE_DIR/.secrets-rendered" 2>/dev/null)" ]; then
    echo -e "  ${GREEN}✅${NC} Secrets already rendered in .secrets-rendered/"
  else
    echo -e "  ${YELLOW}⚠️${NC} Secrets not yet rendered"
    if confirm "Decrypt SOPS secrets now?"; then
      if [ "$DRY_RUN" = false ]; then
        bash "$BASE_DIR/scripts/deploy/render-secrets.sh" || echo -e "  ${YELLOW}  Warning: some secrets may not have decrypted (expected if no age key matched)${NC}"
      else
        echo -e "  ${YELLOW}  (dry-run: would run render-secrets.sh)${NC}"
      fi
    fi
  fi
else
  echo -e "  ${YELLOW}⚠️${NC} Can't render secrets — SOPS or age key missing"
fi

# ────────────────────────────────────────────────────────────────────
step_header "Step 8: Final Validation"
# ────────────────────────────────────────────────────────────────────
echo "Running: cd $BASE_DIR && make validate"
echo ""
if [ "$DRY_RUN" = false ]; then
  cd "$BASE_DIR"
  if make validate; then
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  All checks passed — ready to deploy!        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. bash scripts/deploy/deploy.sh all --dry-run"
    echo "  2. bash scripts/deploy/deploy.sh all"
    echo "  3. bash scripts/deploy/healthcheck.sh"
    echo "  4. bash scripts/deploy/verify-traffic.sh"
  else
    echo ""
    echo -e "${RED}❌ Validation failed. Fix issues above before deploying.${NC}"
    exit 1
  fi
else
  echo -e "  ${YELLOW}  (dry-run: would run make validate)${NC}"
  echo ""
  echo -e "${YELLOW}Dry-run complete. Run without --dry-run to execute.${NC}"
fi

echo ""
echo -e "${GREEN}Done.${NC}"