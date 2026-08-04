#!/bin/bash
# CircuitHQ — Docker Installation Guide (macOS)
# This script is a documented guide — it checks which Docker runtime is installed
# and provides instructions. It does NOT install software automatically.
set -euo pipefail

echo "=== CircuitHQ Docker Setup (macOS) ==="
echo ""
echo "Recommended Docker runtimes for M3 Mac:"
echo ""
echo "  1) OrbStack (recommended) — https://orbstack.dev"
echo "     Lightweight, fast, native ARM64, excellent Docker socket perf"
echo "     brew install orbstack"
echo ""
echo "  2) Docker Desktop — https://docker.com/products/docker-desktop/"
echo "     Most common, full feature set"
echo "     brew install --cask docker"
echo ""
echo "  3) Colima — https://github.com/abiosoft/colima"
echo "     Open-source, lightweight, Lima-based"
echo "     brew install colima"
echo ""

# Detect current runtime
if command -v orb &>/dev/null; then
  echo "✅ OrbStack detected"
elif [ -f "/Applications/Docker.app/Contents/Resources/bin/docker" ] || \
     [ -f "~/Library/Group Containers/group.com.docker/docker" ]; then
  echo "✅ Docker Desktop detected"
elif command -v colima &>/dev/null; then
  echo "✅ Colima detected"
elif command -v docker &>/dev/null; then
  echo "✅ Docker binary found (runtime uncertain)"
else
  echo "❌ No Docker runtime detected"
  echo ""
  echo "Install one of the options above, then re-run this check."
fi

# Verify Docker Compose plugin
echo ""
if docker compose version &>/dev/null; then
  echo "✅ Docker Compose plugin available"
else
  echo "❌ Docker Compose plugin not available"
  echo "   Docker Desktop and OrbStack include it by default."
  echo "   For Colima: brew install docker-compose"
fi

echo ""
echo "=== After installing Docker ==="
echo "1. Start your Docker runtime"
echo "2. Run: docker version"
echo "3. Run: docker compose version"
echo "4. Run: scripts/bootstrap/00-check-host.sh"
echo "5. Run: scripts/bootstrap/02-create-networks.sh"
echo ""
echo "Done."