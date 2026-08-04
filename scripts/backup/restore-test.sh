#!/bin/bash
# CircuitHQ — Automated Restore Test
# ====================================
# Verifies that the latest backup can be restored and key files are present.
# Runs after every backup to ensure backup integrity end-to-end.
#
# Usage:
#   ./scripts/backup/restore-test.sh              # Test latest snapshot
#   ./scripts/backup/restore-test.sh <snapshot>    # Test specific snapshot
#
# Exit codes:
#   0 — restore test passed
#   1 — restore test failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="/tmp/circuithq-restore-test"
SNAPSHOT="${1:-latest}"

RESTIC_ENV="${RESTIC_ENV:-/etc/circuithq/secrets/restic.env}"
if [ -f "$RESTIC_ENV" ]; then
  set -a; source "$RESTIC_ENV"; set +a
fi

: "${RESTIC_REPOSITORY:?}"
: "${RESTIC_PASSWORD:?}"

echo "=== CircuitHQ Restore Test ==="
echo "Snapshot: $SNAPSHOT"
echo "Test directory: $TEST_DIR"
echo ""

# Clean previous test
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Restore to test directory
echo "📂 Restoring to $TEST_DIR..."
if [ "$SNAPSHOT" = "latest" ]; then
  restic restore latest --target "$TEST_DIR" --tag circuithq --tag repo --verbose 2>&1
else
  restic restore "$SNAPSHOT" --target "$TEST_DIR" --tag circuithq --tag repo --verbose 2>&1
fi
echo ""

# Verify key files exist
echo "🔍 Verifying restored files..."
PASS=true

check_file() {
  if [ -f "$TEST_DIR/$1" ] || [ -f "$TEST_DIR/$1" ]; then
    echo "   ✅ $1"
  else
    echo "   ❌ MISSING: $1"
    PASS=false
  fi
}

check_file "Makefile"
check_file ".sops.yaml"
check_file "compose/networks.yml"
check_file "compose/volumes.yml"
check_file "stacks/proxy/compose.yml"
check_file "stacks/proxy/traefik/static.yml"
check_file "stacks/auth/compose.yml"
check_file "stacks/monitoring/compose.yml"
check_file "stacks/logging/compose.yml"

echo ""
if [ "$PASS" = "true" ]; then
  echo "✅ Restore test PASSED — all key files present"
else
  echo "❌ Restore test FAILED — some files missing"
  exit 1
fi

# Cleanup
rm -rf "$TEST_DIR"
echo "   Test directory cleaned up"