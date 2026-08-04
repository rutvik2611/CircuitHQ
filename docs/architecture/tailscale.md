# Tailscale Architecture

Tailscale provides the private administration and mesh networking plane for CircuitHQ.

## Role

Tailscale is **not** the public ingress plane. Public apps use Cloudflare Tunnel → Traefik.
Tailscale is for:
- SSH to the host
- Private dashboards (Grafana, Prometheus, Traefik dashboard)
- Emergency access when Cloudflare Tunnel is down
- Optional subnet routing to LAN devices
- Optional exit node for remote browsing

## Modes

### Mode 1: Normal Node (Baseline)

```
Admin Device —Tailscale mesh—> CircuitHQ Host
                                 +-- SSH
                                 +-- Private dashboards
                                 +-- Host maintenance
```

Always enabled. The host joins the tailnet as a normal node with MagicDNS.

### Mode 2: Exit Node (Optional)

```
Remote Device —Tailscale—> CircuitHQ Exit Node —> Internet
```

Enable only if remote internet egress through home is needed. ACL-restricted.

### Mode 3: Subnet Router (Optional)

```
Admin Device —Tailscale—> CircuitHQ Subnet Router —> LAN (192.168.x.x)
```

Enable only if LAN devices (NAS, printers) need Tailscale access.

## MagicDNS

All hosts get a `hostname.tailnet-name.ts.net` DNS name. Enable with:
```bash
tailscale set --accept-dns
```

## Tailscale SSH

Replace or supplement OpenSSH with Tailscale SSH for ACL-aware SSH:
```bash
tailscale set --ssh
```

## ACL Model

See `infra/tailscale/policy.hujson` for the full ACL definitions.

Key groups:
- `group:admin` — full SSH + private dashboard access
- `group:ci` — restricted CI operations
- `tag:ci`, `tag:prod`, `tag:monitoring`, etc. — device-level tags

## Traffic Flow for Private Admin

```
User Browser / Terminal
  |
  | Tailscale encrypted mesh (WireGuard)
  v
CircuitHQ Host
  |
  +-- SSH (port 22)
  +-- Grafana (port 3000)
  +-- Prometheus (port 9090)
  +-- Traefik dashboard (internal port)
```