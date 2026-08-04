#!/bin/bash
# CircuitHQ — Host Prerequisites Check
# Verifies the minimum requirements for running the homelab platform
set -euo pipefail

echo "=== CircuitHQ Host Bootstrap Check ==="
echo ""

# OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"
echo "OS: $OS"
echo "Architecture: $ARCH"

case "$ARCH" in
  arm64|aarch64)
    echo "✅ ARM64 architecture detected — native Docker support"
    ;;
  x86_64|amd64)
    echo "⚠️  x86_64 architecture — may need emulation for ARM64 images"
    ;;
  *)
    echo "⚠️  Unknown architecture: $ARCH — compatibility not guaranteed"
    ;;
esac

# Docker
echo ""
echo "--- Docker ---"
if command -v docker &>/dev/null; then
  DOCKER_VER="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown')"
  echo "✅ Docker version: $DOCKER_VER"
else
  echo "❌ Docker not found — install Docker Desktop, OrbStack, or Colima"
fi

# Docker Compose
echo ""
echo "--- Docker Compose ---"
if docker compose version &>/dev/null; then
  COMPOSE_VER="$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null)"
  echo "✅ Docker Compose: $COMPOSE_VER"
else
  echo "❌ Docker Compose plugin not found"
fi

# Disk space
echo ""
echo "--- Disk Space ---"
AVAIL_KB="$(df -k / | awk 'NR==2 {print $4}')"
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
echo "Available disk: ${AVAIL_GB}GB"
if [ "$AVAIL_GB" -lt 10 ]; then
  echo "❌ Less than 10GB available — homelab needs at least 20GB"
elif [ "$AVAIL_GB" -lt 20 ]; then
  echo "⚠️  Less than 20GB available — consider freeing space"
else
  echo "✅ Sufficient disk space"
fi

# Memory
echo ""
echo "--- Memory ---"
if command -v sysctl &>/dev/null; then
  MEM_GB="$(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024}')"
  echo "Memory: ${MEM_GB}GB"
  if [ "$(echo "$MEM_GB < 8" | bc -l)" -eq 1 ]; then
    echo "⚠️  Less than 8GB RAM — monitoring stack may be constrained"
  else
    echo "✅ Sufficient memory"
  fi
elif command -v free &>/dev/null; then
  free -h | head -2
fi

echo ""
echo "=== Check Complete ==="