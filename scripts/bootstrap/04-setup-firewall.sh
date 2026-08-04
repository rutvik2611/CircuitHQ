#!/bin/bash
# CircuitHQ — macOS Firewall Setup Guide
# macOS uses the built-in application firewall (socketfilterfw).
# There is no nftables/iptables on macOS.
#
# This script checks and documents the firewall state.
set -euo pipefail

echo "=== CircuitHQ Firewall Setup (macOS) ==="
echo ""
echo "macOS uses the built-in Application Firewall (PF is available but complex)."
echo ""

# Check built-in firewall
if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
  echo "✅ macOS Application Firewall: ENABLED"
else
  echo "⚠️  macOS Application Firewall: DISABLED"
  echo "   Enable it: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
fi

# Check if stealth mode is on
if /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null | grep -q "enabled"; then
  echo "✅ Stealth mode: ENABLED"
else
  echo "⚠️  Stealth mode: DISABLED"
  echo "   Enable it: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"
fi

echo ""
echo "--- Firewall Best Practices for Homelab on macOS ---"
echo ""
echo "1. Enable the built-in firewall (steps above)"
echo "2. Enable stealth mode (steps above)"
echo "3. Disable remote login (SSH) unless needed:"
echo "   System Settings > General > Sharing > Remote Login"
echo "4. If you need remote SSH, restrict to Tailscale interface only:"
echo "   - Install Tailscale and use Tailscale SSH"
echo "   - Or use PF to restrict SSH to Tailscale IP range (100.64.0.0/10)"
echo "5. Docker networks are internal — they don't need firewall rules"
echo "6. No router port forwards should be configured for public ingress"
echo "   (Cloudflare Tunnel handles public access outbound)"
echo ""
echo "--- PF (Packet Filter) Notes ---"
echo ""
echo "macOS has PF (pfctl) for advanced rules. Example PF anchor for Docker:"
echo ""
echo "  # /etc/pf.anchors/circuithq"
echo "  # Block inbound by default on en0 (Tailscale handles admin)"
echo "  block in on en0 proto tcp"
echo "  pass in on utun0 proto tcp    # Tailscale interface"
echo ""
echo "PF is optional for most homelab setups with the built-in firewall enabled."
echo ""

echo "=== Firewall check complete ==="