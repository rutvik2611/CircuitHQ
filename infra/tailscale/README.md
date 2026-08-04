# Tailscale

Tailscale provides the private administration and mesh networking plane for CircuitHQ.

## Design Overview

- **Normal node + MagicDNS** is the day-one baseline
- **Exit node** and **subnet router** modes are optional, ACL-restricted
- Tailscale is NOT the public ingress — Cloudflare Tunnel + Traefik handle that
- ACLs are defined as code in `policy.hujson`

## Baseline Setup

1. Install Tailscale on the host: `brew install tailscale`
2. Authenticate and join your tailnet: `tailscale up`
3. Enable MagicDNS: `tailscale set --accept-dns`
4. Enable Tailscale SSH: `tailscale set --ssh`
5. Tag the device: `tailscale up --advertise-tags=tag:server,tag:prod`

## Tags Reference

| Tag | Purpose |
|-----|---------|
| `tag:prod` | Production services |
| `tag:server` | Generic server hosts |
| `tag:pikvm` | PiKVM devices |
| `tag:monitoring` | Monitoring services |
| `tag:ci` | CI runners |
| `tag:backup` | Backup nodes |
| `tag:exit-node` | Exit node capability |
| `tag:subnet-router` | Subnet routing capability |

## ACL Model

- `group:admin` — full SSH + private dashboard access
- `group:ci` — restricted to CI operations only
- `tag:ci` — CI runner can access only required endpoints
- Exit node and subnet router tags require explicit ACL approval

## File Layout

```
infra/tailscale/
├── README.md          # This file
└── policy.hujson      # ACL policy definition
```