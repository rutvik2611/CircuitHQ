# Tailscale Recovery Runbook

## Scenario 1: Tailscale Service Down on Host

**Symptoms:** Cannot SSH over Tailscale, `tailscale status` shows nothing

**Impact:** Private admin access lost; public apps still work through Cloudflare Tunnel

**Recovery:**

```bash
# Check service status
sudo tailscale status
tailscale version

# Restart Tailscale
sudo tailscale down
sudo tailscale up

# Re-authenticate if needed
sudo tailscale up --advertise-tags=tag:prod,tag:server
```

## Scenario 2: Authentication Expired

**Symptoms:** `tailscale status` shows the node but connections fail

**Recovery:**

```bash
sudo tailscale logout
sudo tailscale up --advertise-tags=tag:prod,tag:server
# Complete browser-based auth
```

## Scenario 3: Cannot Reach Tailscale Coordination Server

**Symptoms:** Tailscale running but no peers connectable

**Impact:** DERP relay may allow some connectivity; direct peer-to-peer fails

**Recovery:**

```bash
# Check DERP status
tailscale derpmap

# Force a DERP relay
tailscale status --json | grep -i derp

# If DERP also fails, use local console or OpenSSH fallback
# Check internet connectivity
ping google.com
```

## Scenario 4: ACL Misconfiguration Locks Admin Out

**Symptoms:** After applying a bad policy.hujson, SSH/svc access stops working

**Recovery:**

1. Use local console or OpenSSH (non-Tailscale) as fallback
2. Revert ACL changes in the Tailscale admin console
3. Or apply known-good policy:
   ```bash
   # The fallback OpenSSH must be configured (see host bootstrap)
   ssh localhost
   # Then fix ACLs through admin console or API
   ```

## Fallback: OpenSSH (Non-Tailscale)

Always configure a local OpenSSH fallback locked to Tailscale IP range:

```
# /etc/ssh/sshd_config.d/99-tailscale-only.conf
ListenAddress 100.64.0.0/10
ListenAddress 127.0.0.1
```

This ensures SSH is only reachable over Tailscale or localhost.

## Prevention

1. Test ACL changes on a non-production device first
2. Keep a local console or IPMI/KVM access available
3. Document the Tailscale admin console recovery URL
4. Maintain an offline backup of the admin login credentials
5. Use the `tests` section in policy.hujson to validate ACLs before applying