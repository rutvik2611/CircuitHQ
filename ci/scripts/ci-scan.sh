#!/bin/bash
# CircuitHQ — CI Security Scan
# ==============================
# Runs Trivy filesystem scan and Syft SBOM generation.
# Intended for CI pipelines (GitHub Actions) and local validation.
#
# Usage:
#   ./ci/scripts/ci-scan.sh                    # Full scan
#   ./ci/scripts/ci-scan.sh --quick            # Skip SBOM, faster
#   ./ci/scripts/ci-scan.sh --sbom-only        # Only generate SBOM

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-full}"
EXIT_CODE=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "=== CircuitHQ CI Security Scan ==="
echo "Mode: $MODE"
echo ""

# ── Trivy Filesystem Scan ────────────────────────────────────────────
if [ "$MODE" != "--sbom-only" ]; then
  if command -v trivy &>/dev/null; then
    echo "🔍 Running Trivy filesystem scan..."
    echo "   Scanners: config, vuln, secret"
    echo ""

    if trivy fs --scanners config,vuln,secret --quiet \
      --severity CRITICAL,HIGH \
      --exit-code 1 \
      --ignore-unfixed \
      "$BASE_DIR" 2>/dev/null; then
      echo -e "${GREEN}✅${NC} Trivy: no critical/high vulnerabilities found"
    else
      echo -e "${RED}❌${NC} Trivy: critical/high vulnerabilities detected"
      EXIT_CODE=1
    fi
  else
    echo -e "${YELLOW}⚠️${NC} trivy not installed — skipping filesystem scan"
  fi
fi

# ── Syft SBOM Generation ─────────────────────────────────────────────
if [ "$MODE" != "--quick" ]; then
  if command -v syft &>/dev/null; then
    echo ""
    echo "📦 Generating SBOM (Syft)..."
    mkdir -p "$BASE_DIR/ci-artifacts"

    # Generate SBOM for repository dependencies
    # Checks for package manifests
    SBOM_FILE="$BASE_DIR/ci-artifacts/sbom.cirquthq.json"
    if syft dir:"$BASE_DIR" --output json --file "$SBOM_FILE" 2>/dev/null; then
      echo -e "${GREEN}✅${NC} SBOM generated: ci-artifacts/sbom.circuithq.json"
    else
      echo -e "${YELLOW}⚠️${NC} Syft SBOM generation had issues"
    fi
  else
    echo -e "${YELLOW}⚠️${NC} syft not installed — skipping SBOM generation"
  fi
fi

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
  echo -e "${GREEN}✅${NC} Security scan completed successfully"
else
  echo -e "${RED}❌${NC} Security scan failed — review findings above"
fi
exit $EXIT_CODE