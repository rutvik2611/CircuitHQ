# Architecture, Networking, and Service Design

> Split from `HOMELAB_PLATFORM_BLUEPRINT.md` on 2026-08-04. The original giant file is retained as an archive/source reference.

Core platform architecture: goals, diagrams, Tailscale, Docker networks, Traefik, and service categories.

## Local Table of Contents

- [1. Executive Summary](#1-executive-summary)
- [2. Core Architecture Principles](#2-core-architecture-principles)
- [3. High-Level Architecture Diagram](#3-high-level-architecture-diagram)
- [4. Detailed Infrastructure Diagram](#4-detailed-infrastructure-diagram)
- [5. Network Diagram](#5-network-diagram)
- [6. Tailscale Architecture](#6-tailscale-architecture)
- [7. Docker Network Design](#7-docker-network-design)
- [8. Reverse Proxy Architecture: Traefik](#8-reverse-proxy-architecture-traefik)
- [9. Service Design](#9-service-design)

---

# 1. Executive Summary

This document designs a production-grade, enterprise-quality homelab platform that starts on a single PiKVM V4 and scales naturally to additional nodes later. The platform uses only free software wherever practical, with no paid SaaS required. Public access is provided through Cloudflare DNS and Cloudflare Tunnel into Traefik. No inbound router ports are exposed directly.

The platform is intentionally designed like a miniature cloud platform:

- **Ingress layer:** Cloudflare Tunnel and Traefik.
- **Private access layer:** Tailscale with MagicDNS, ACLs, SSH, subnet routing, and optional exit-node patterns.
- **Runtime layer:** Docker Compose today; multi-host Docker, Nomad, or Kubernetes later.
- **Network layer:** multiple purpose-built Docker networks with least-privilege attachment.
- **Security layer:** non-root containers, capability dropping, read-only filesystems, SOPS + age secrets, CrowdSec, fail2ban where useful, firewall deny-by-default.
- **Observability layer:** Prometheus, Grafana, Loki, Promtail or Alloy, cAdvisor, Node Exporter, Alertmanager, Uptime Kuma.
- **Backup layer:** restic or BorgBackup with encrypted local/NAS/SFTP targets, scheduled verification, and restore tests.
- **Delivery layer:** GitOps-inspired repo structure, CI validation, manual approvals, deployment manifests, health checks, traffic verification, and rollback.

The starting architecture is intentionally over-engineered for a single node because the goal is long-term stability, maintainability, observability, security, and reliability.

---

---

# 2. Core Architecture Principles

## 2.1 Non-negotiable goals

| Goal | Design choice |
|---|---|
| 100% free software where possible | Docker CE, Compose, Traefik, Prometheus, Grafana OSS, Loki, restic, SOPS, age, Forgejo/Gitea/Woodpecker optional |
| Extremely stable | Pin versions, health checks, restart policies, backups, rollback, staging validation |
| Production ready | Separation of environments, runbooks, monitoring, alerting, least privilege |
| Self-documenting | Repo-first documentation, architecture decision records, diagrams, service READMEs |
| Highly modular | One service stack per folder, shared networks, reusable templates |
| Secure by default | No exposed ports, Cloudflare Tunnel, Traefik auth, Tailscale ACLs, secrets encryption |
| Easily expandable | Docker Compose now, labels and network conventions transferable to Swarm/Nomad/Kubernetes |
| GitOps-inspired | Git is source of truth, CI validates, manual deploy approvals, audited releases |
| Zero vendor lock-in | Cloudflare is isolated to tunnel/DNS; Traefik configs and Compose remain portable |
| No paid SaaS required | Self-hosted CI option, self-hosted monitoring/logging/backups |

## 2.2 Important pragmatic note about Cloudflare

Cloudflare DNS and Cloudflare Tunnel are free to use but Cloudflare itself is a third-party cloud service. Because the requested ingress path explicitly requires Cloudflare DNS and Tunnel, this design uses Cloudflare as the public edge. To reduce lock-in:

- Traefik remains the real application ingress controller.
- Public service routes are defined in repo, not only in Cloudflare UI.
- Tunnel config is versioned without secrets.
- Services can be moved to another tunnel provider, VPS reverse proxy, WireGuard, Tailscale Funnel, or direct DNS later.
- Internal/private access never depends exclusively on Cloudflare because Tailscale provides a separate administration plane.

## 2.3 Platform maturity model

| Level | Description | Target state |
|---|---|---|
| Level 0 | Ad-hoc Docker host | Avoid |
| Level 1 | Organized Compose apps | Phase 1 |
| Level 2 | Secure ingress + private admin | Phase 2 |
| Level 3 | Monitoring, logging, backups | Phase 3 |
| Level 4 | CI validation + manual deploy | Phase 4 |
| Level 5 | Automated rollback + DR tests | Phase 5 |
| Level 6 | Multi-node expansion | Phase 6+ |

---

---

# 3. High-Level Architecture Diagram

```text
                                      +----------------------+
                                      |      Developer       |
                                      |  Laptop / Workstation|
                                      +----------+-----------+
                                                 |
                                                 | Git push / PR
                                                 v
                                      +----------------------+
                                      |   Git Repository     |
                                      | GitHub / Forgejo     |
                                      +----------+-----------+
                                                 |
                                                 | CI validation
                                                 v
                                      +----------------------+
                                      |   Free CI System     |
                                      | Actions/Woodpecker   |
                                      +----------+-----------+
                                                 | manual approval
                                                 v
+--------------+      +--------------+      +----------------------+
|   Internet   |----->| Cloudflare   |----->| Cloudflare Tunnel    |
|   Clients    | DNS  | DNS / Edge   |      | cloudflared container|
+--------------+      +--------------+      +----------+-----------+
                                                         | private tunnel
                                                         v
                                                  +-------------+
                                                  |   Traefik   |
                                                  | Reverse     |
                                                  | Proxy       |
                                                  +------+------+
                                                         |
                        +--------------------------------+--------------------------------+
                        v                                v                                v
              +-----------------+              +-----------------+              +-----------------+
              | Public Apps     |              | Auth / Infra    |              | Monitoring      |
              | websites, APIs  |              | Authelia, DNS   |              | Grafana, Loki   |
              +-----------------+              +-----------------+              +-----------------+

+----------------------+
| Tailscale Private    |
| Admin Plane          |
| SSH, MagicDNS, ACLs  |
+----------+-----------+
           |
           v
+----------------------+
| PiKVM V4 Host        |
| Docker + Compose     |
| Backups + Monitoring |
+----------------------+
```

---

---

# 4. Detailed Infrastructure Diagram

```text
+-----------------------------------------------------------------------------+
|                             PUBLIC INTERNET                                  |
+-----------------------------------------------------------------------------+
                                      |
                                      v
+-----------------------------------------------------------------------------+
|                              CLOUDFLARE                                      |
|                                                                             |
|  +---------------+     +----------------+     +-------------------------+  |
|  | DNS Zone      |---->| Edge Network   |---->| Zero Trust Tunnel Route |  |
|  | example.com   |     | HTTPS/WAF DNS  |     | *.example.com           |  |
|  +---------------+     +----------------+     +-------------------------+  |
+-----------------------------------------------------------------------------+
                                      |
                                      | outbound-only tunnel from homelab
                                      v
+-----------------------------------------------------------------------------+
|                            HOME / LAB NETWORK                                |
|                                                                             |
|  Router/firewall                                                             |
|  - No inbound service port forwards                                          |
|  - Optional outbound restrictions                                            |
|  - Optional local VLANs later                                                |
|                                                                             |
|  +-----------------------------------------------------------------------+  |
|  |                            PiKVM V4 Host                              |  |
|  |                                                                       |  |
|  |  Base OS                                                              |  |
|  |  - SSH restricted by Tailscale/firewall                               |  |
|  |  - Docker CE + Docker Compose plugin                                  |  |
|  |  - systemd timers for backup/maintenance                              |  |
|  |  - nftables or ufw deny-by-default                                    |  |
|  |                                                                       |  |
|  |  +---------------------+       +---------------------+               |  |
|  |  | Tailscale daemon    |       | cloudflared         |               |  |
|  |  | Private admin plane |       | outbound tunnel     |               |  |
|  |  +----------+----------+       +----------+----------+               |  |
|  |             |                             |                          |  |
|  |             v                             v                          |  |
|  |  +-------------------------------------------------------+            |  |
|  |  | Traefik reverse proxy                                 |            |  |
|  |  | - Routers, services, middlewares                       |            |  |
|  |  | - TLS, headers, auth, rate limits                      |            |  |
|  |  | - Dashboard protected                                  |            |  |
|  |  +----------+------------------------------+-------------+            |  |
|  |             |                              |                          |  |
|  |             v                              v                          |  |
|  |  +---------------------+       +---------------------+               |  |
|  |  | Public service zone |       | Management zone     |               |  |
|  |  | websites/APIs       |       | Portainer optional  |               |  |
|  |  +---------------------+       +---------------------+               |  |
|  |                                                                       |  |
|  |  +---------------------+       +---------------------+               |  |
|  |  | Monitoring zone     |       | Database zone       |               |  |
|  |  | Prom/Grafana/Loki   |       | Postgres/Redis/etc  |               |  |
|  |  +---------------------+       +---------------------+               |  |
|  |                                                                       |  |
|  |  +---------------------+       +---------------------+               |  |
|  |  | Backup zone         |       | Shared utilities    |               |  |
|  |  | restic/Borg         |       | Watchtower optional |               |  |
|  |  +---------------------+       +---------------------+               |  |
|  +-----------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------+
```

---

---

# 5. Network Diagram

## 5.1 Physical and logical network

```text
Internet
   |
   | HTTPS to Cloudflare only
   v
Cloudflare Edge
   |
   | Cloudflare Tunnel, outbound from homelab
   v
Home Router / Firewall
   |
   | No inbound port forwards
   | LAN egress allowed for tunnel, updates, DNS, NTP
   v
PiKVM V4 Host
   |
   +-- Tailscale interface: tailscale0
   |      +-- private admin SSH
   |      +-- MagicDNS
   |      +-- optional subnet routes
   |      +-- optional exit node
   |
   +-- Docker bridge networks
   |      +-- proxy
   |      +-- public
   |      +-- private
   |      +-- management
   |      +-- monitoring
   |      +-- database
   |      +-- shared
   |      +-- backup
   |
   +-- Host-only services
          +-- Docker daemon
          +-- systemd timers
          +-- nftables/ufw
          +-- backup scripts
```

## 5.2 Traffic classes

| Traffic class | Path | Allowed? | Notes |
|---|---|---:|---|
| Public user to app | Internet -> Cloudflare -> Tunnel -> Traefik -> app | Yes | No direct port exposure |
| Admin SSH | Admin device -> Tailscale -> host SSH | Yes | ACL restricted |
| App to database | App network -> database network | Yes, per service | Only specific app containers attach to database network |
| Public app to management | public -> management | No | Hard separation |
| Monitoring scrape | Prometheus -> exporters/apps | Yes | Pull-based, restricted network membership |
| Backup read | backup job -> volumes/configs | Yes | Read-only where possible |
| Database to internet | database -> internet | Prefer no | Only for updates during maintenance if needed |
| Container to Docker socket | container -> `/var/run/docker.sock` | Avoid | If required, use socket proxy |

---

---

# 6. Tailscale Architecture

Tailscale is the private administration and mesh networking plane. It is not the primary public ingress plane. Public apps use Cloudflare Tunnel and Traefik. Tailscale is used for safe administration, private-only services, emergency access, subnet routing, and optional exit-node capabilities.

## 6.1 Baseline Tailscale design

Recommended baseline:

- Install Tailscale on the host OS, not only inside a container.
- Enable MagicDNS.
- Use ACLs with least privilege.
- Use device tags for servers and automation.
- Use Tailscale SSH for emergency access or restrict OpenSSH to Tailscale IPs.
- Do not make every service public through Tailscale Serve/Funnel by default.
- Prefer private admin via Tailscale over exposing management dashboards through Cloudflare.

## 6.2 Tailscale traffic flow overview

```text
Admin Laptop / Phone
   |
   | Tailscale encrypted WireGuard mesh
   v
Tailscale Coordination Control Plane
   |
   | peer discovery + policy, not data path in normal direct mode
   v
PiKVM V4 tailscale0
   |
   +-- SSH to host
   +-- Access private dashboards
   +-- Reach Docker services bound to host/Tailscale only
   +-- Optional route to LAN subnets
   +-- Optional exit-node internet egress
```

## 6.3 Mode 1: Normal Node

### Diagram

```text
Admin Device --Tailscale mesh--> PiKVM V4
                                  +-- SSH
                                  +-- private dashboards
                                  +-- host maintenance
```

### Architecture

The PiKVM V4 joins the tailnet as a normal node. It receives a `100.x.y.z` Tailscale IP and MagicDNS name such as `pikvm-prod.tailnet.ts.net`.

### Traffic flow

1. Admin device connects to tailnet.
2. Admin accesses `ssh pikvm-prod` or private service URLs.
3. Traffic uses direct WireGuard peer-to-peer where possible.
4. DERP relay is used only when direct NAT traversal fails.

### Advantages

- Simple and stable.
- Excellent for private administration.
- No router port forwarding.
- Works from laptop, phone, tablet, or another server.

### Disadvantages

- Does not provide LAN access unless subnet routing is enabled.
- Does not route internet traffic unless exit node is enabled.

### Use cases

- Daily SSH administration.
- Private Grafana, Portainer, Prometheus, Uptime Kuma access.
- Emergency maintenance when public tunnel breaks.

### Enable when

Always enable this as the baseline mode.

---

## 6.4 Mode 2: Exit Node

### Diagram

```text
Remote Device --Tailscale--> PiKVM V4 Exit Node --> Internet
```

### Architecture

The PiKVM advertises itself as an exit node. Remote devices can choose it as their internet gateway.

### Traffic flow

1. Remote device selects PiKVM as exit node.
2. Internet-bound traffic goes through the Tailscale tunnel to the PiKVM.
3. PiKVM NATs traffic out through the home internet connection.

### Advantages

- Secure browsing over trusted home network while traveling.
- Access geo/home-IP-restricted resources.
- Useful fallback VPN.

### Disadvantages

- Can consume PiKVM CPU and home upload bandwidth.
- If misconfigured, DNS may leak.
- Home network reputation can be affected by remote device traffic.
- Exit node availability depends on home ISP/power.

### Use cases

- Travel VPN.
- Admin from untrusted Wi-Fi.
- Access services that only allow home IP.

### Enable when

Enable only if you need remote internet egress through home. Do not enable by default on weak hardware if bandwidth or CPU is limited.

---

## 6.5 Mode 3: Exit Node + DNS

### Diagram

```text
Remote Device
   | all traffic + DNS
   v
PiKVM Exit Node
   | DNS queries
   v
Chosen DNS Resolver
   +-- router DNS
   +-- Unbound
   +-- AdGuard Home
   +-- Pi-hole
```

### Architecture

The exit node is combined with controlled DNS. Remote clients use the tailnet DNS configuration while routing through the exit node.

### Traffic flow

1. Remote device selects exit node.
2. DNS is resolved using tailnet DNS or a specified internal resolver.
3. All internet traffic exits through PiKVM.

### Advantages

- Avoids DNS leaks.
- Centralizes DNS policy.
- Enables internal hostnames and split DNS.

### Disadvantages

- DNS resolver becomes a critical dependency.
- Misconfigured DNS can break remote internet access.

### Use cases

- Travel with consistent DNS.
- Internal name resolution while using exit node.
- Enforced family/security DNS.

### Enable when

Enable when exit-node users also need consistent DNS, internal domain resolution, or ad/security filtering.

---

## 6.6 Mode 4: Exit Node + AdGuard Home

### Diagram

```text
Remote Device --Tailscale--> PiKVM Exit Node
                                  |
                                  v
                            AdGuard Home
                                  |
                                  v
                              Internet DNS
```

### Architecture

AdGuard Home runs as a container or host service. Tailscale DNS points clients to AdGuard Home. Exit-node clients route traffic through PiKVM and DNS through AdGuard.

### Traffic flow

1. Client enables PiKVM exit node.
2. DNS queries go to AdGuard Home.
3. AdGuard blocks ads/malware/tracking based on lists.
4. Allowed queries resolve upstream.
5. Client traffic exits through PiKVM.

### Advantages

- Modern UI.
- Good DNS filtering.
- Per-client policies.
- Easy upstream configuration.

### Disadvantages

- Another service to back up and monitor.
- Blocklists can break sites.
- DNS outage affects clients using it.

### Use cases

- Ad-blocking for remote devices.
- DNS-based malware filtering.
- Centralized DNS visibility.

### Enable when

Enable when you want a polished DNS filtering solution with a modern interface and per-client control.

---

## 6.7 Mode 5: Exit Node + Pi-hole

### Diagram

```text
Remote Device --Tailscale--> PiKVM Exit Node
                                  |
                                  v
                               Pi-hole
                                  |
                                  v
                              Upstream DNS
```

### Architecture

Pi-hole provides DNS blocking. It can run on the PiKVM or a separate Raspberry Pi/NAS later. Tailscale DNS points to Pi-hole.

### Traffic flow

Same as AdGuard Home pattern, but DNS queries are filtered by Pi-hole.

### Advantages

- Very mature.
- Huge community.
- Simple blocklist ecosystem.
- Good for Raspberry Pi style deployments.

### Disadvantages

- UI and policy model can feel less modern than AdGuard.
- Requires careful configuration for Docker networking.
- Another critical dependency if used by all devices.

### Use cases

- Classic homelab DNS filtering.
- Family network DNS blocking.
- Low-resource DNS filtering.

### Enable when

Enable if you prefer Pi-hole ecosystem/community or already use Pi-hole.

---

## 6.8 Mode 6: Subnet Router

### Diagram

```text
Remote Admin Device --Tailscale--> PiKVM Subnet Router --> Home LAN
                                                     |
                                                     +-- NAS
                                                     +-- Printer
                                                     +-- Router UI
                                                     +-- Other LAN devices
```

### Architecture

The PiKVM advertises LAN routes such as `192.168.1.0/24`. Tailnet clients can access devices on the home LAN without exposing VPN ports.

### Traffic flow

1. PiKVM advertises route `192.168.1.0/24`.
2. Tailnet admin approves route.
3. Remote client sends LAN-bound traffic to PiKVM.
4. PiKVM forwards traffic to LAN.
5. LAN devices reply via PiKVM if routing/NAT is configured.

### Advantages

- Remote access to LAN devices.
- Useful for NAS, router, printers, IPMI, additional PiKVMs.
- No traditional VPN server required.

### Disadvantages

- Increases blast radius if ACLs are weak.
- Requires IP forwarding and route approval.
- LAN devices may not have host firewalls.

### Use cases

- Remote access to NAS web UI.
- Router admin during travel.
- SSH into other LAN servers.
- Manage future Docker nodes before joining Tailscale.

### Enable when

Enable when you need controlled remote access to LAN subnets. Restrict with ACLs.

---

## 6.9 Mode 7: Exit Node + Subnet Router

### Diagram

```text
Remote Device
   |
   +-- Internet traffic --> PiKVM Exit Node --> Internet
   |
   +-- LAN traffic ------> PiKVM Subnet Router --> Home LAN
```

### Architecture

The PiKVM acts as both an exit node and a subnet router. Remote devices can route all internet traffic and selected LAN traffic through PiKVM.

### Advantages

- Full remote network experience.
- Powerful travel/admin setup.
- One node provides internet egress and LAN access.

### Disadvantages

- More complex.
- Higher CPU/bandwidth load.
- Larger security blast radius.
- Must use strict ACLs and monitoring.

### Use cases

- Traveling administrator needs full home network access.
- Emergency recovery from remote location.
- Temporary mobile office through home network.

### Enable when

Enable only for trusted admin devices and only after normal node and subnet routing are stable.

---

## 6.10 Mode 8: Tailscale Serve

### Diagram

```text
Tailnet Client --HTTPS over Tailscale--> Tailscale Serve on PiKVM --> Local service
```

### Architecture

Tailscale Serve exposes a local service only to tailnet members using a Tailscale-provided HTTPS endpoint.

### Advantages

- Simple private HTTPS access.
- No public internet exposure.
- Good for admin-only tools.

### Disadvantages

- Separate routing plane from Traefik.
- Can create configuration sprawl if overused.
- Not ideal for complex middleware/auth chains.

### Use cases

- Temporary private access to a service.
- Admin dashboard that should not go through Cloudflare.
- Testing a service before adding Traefik route.

### Enable when

Use for private-only, low-complexity tools or temporary access. Prefer Traefik for long-term standardized routing.

---

## 6.11 Mode 9: Tailscale Funnel

### Diagram

```text
Internet Client --HTTPS--> Tailscale Funnel --> PiKVM local service
```

### Architecture

Tailscale Funnel exposes a local service publicly through Tailscale infrastructure.

### Advantages

- No router port forwards.
- Useful alternative to Cloudflare Tunnel.
- Easy temporary public sharing.

### Disadvantages

- Public exposure path outside Cloudflare/Traefik standard.
- May bypass central Traefik security middleware.
- Depends on Tailscale feature availability/policy.

### Use cases

- Temporary public demo.
- Backup public ingress path.
- Emergency publishing if Cloudflare tunnel fails.

### Enable when

Use sparingly. For production public services, prefer Cloudflare Tunnel -> Traefik as the standard path.

---

## 6.12 Mode 10: MagicDNS

### Diagram

```text
Admin Device -- pikvm-prod.tailnet-name.ts.net --> PiKVM Tailscale IP
```

### Architecture

MagicDNS provides stable internal names for tailnet devices.

### Advantages

- Avoids memorizing Tailscale IPs.
- Simplifies runbooks.
- Works well with SSH and private dashboards.

### Disadvantages

- Depends on Tailscale DNS settings.
- Naming discipline is still required.

### Use cases

- `ssh pikvm-prod`
- `https://grafana.pikvm-prod.tailnet-name.ts.net`
- private admin bookmarks.

### Enable when

Always enable unless there is a specific DNS conflict.

---

## 6.13 ACLs

### Architecture

ACLs define which users, groups, devices, and tags can communicate. ACLs should be maintained as code in the infrastructure repository and reviewed before changes.

### Policy principles

- Default deny mindset.
- Admin group can SSH to servers.
- Monitoring nodes can scrape exporters.
- Automation tags can deploy only to required hosts.
- Regular users cannot access management networks.
- Subnet routes are restricted to admins.
- Exit nodes are restricted to trusted users/devices.

### Example policy concepts

```jsonc
{
  "groups": {
    "group:admins": ["admin@example.com"],
    "group:operators": ["operator@example.com"]
  },
  "tagOwners": {
    "tag:server": ["group:admins"],
    "tag:prod": ["group:admins"],
    "tag:ci": ["group:admins"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:server:*"]
    },
    {
      "action": "accept",
      "src": ["tag:ci"],
      "dst": ["tag:prod:22"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:server"],
      "users": ["admin", "root"]
    }
  ]
}
```

### Enable when

Always use ACLs once more than one user or more than one device exists. For production design, implement ACLs from day one.

---

## 6.14 Device tags

### Recommended tags

| Tag | Purpose |
|---|---|
| `tag:prod` | Production infrastructure nodes |
| `tag:server` | Server-class nodes |
| `tag:pikvm` | PiKVM-specific node |
| `tag:monitoring` | Monitoring nodes/services |
| `tag:ci` | CI deploy runners |
| `tag:backup` | Backup nodes |
| `tag:exit-node` | Approved exit nodes |
| `tag:subnet-router` | Approved subnet routers |

### Enable when

Use tags immediately for servers. Tags make ACLs stable even when people or devices change.

---

## 6.15 Tailscale SSH

### Architecture

Tailscale SSH can replace or supplement OpenSSH access. It enforces identity-aware access based on tailnet policy.

### Advantages

- Identity-aware SSH policy.
- No need to distribute SSH public keys to every host.
- Good auditability through Tailscale logs.

### Disadvantages

- Depends on Tailscale control plane.
- Some administrators prefer traditional SSH keys.
- Emergency local access should still exist.

### Recommendation

Use both:

- Tailscale SSH for normal remote administration.
- OpenSSH bound/restricted to Tailscale and local console for break-glass.
- Keep a local emergency admin account with strong credentials and hardware/local access path.

---

## 6.16 High availability considerations

Tailscale HA is about avoiding single points for routes and exit nodes.

### Patterns

| Pattern | Description |
|---|---|
| Multiple normal nodes | Each server joins tailnet directly |
| Multiple subnet routers | Two nodes advertise same LAN route |
| Multiple exit nodes | Laptop can choose alternate exit node |
| Router on NAS/NUC | More stable than PiKVM if PiKVM is overloaded |
| Dedicated DNS pair | AdGuard/Pi-hole primary and secondary |

### Recommendation

Today:

- PiKVM as normal node.
- Optional subnet router if needed.
- Avoid exit node until baseline monitoring exists.

Future:

- Add NUC/NAS as second subnet router.
- Add at least two DNS resolvers.
- Add multiple exit nodes if remote work depends on them.

---

## 6.17 Split DNS

### Architecture

Split DNS sends selected domains to specific resolvers.

Examples:

| Domain | Resolver |
|---|---|
| `home.arpa` | local AdGuard/Pi-hole/Unbound |
| `lab.internal` | local DNS resolver |
| `tailnet.ts.net` | Tailscale MagicDNS |
| public domain | public DNS/Cloudflare |

### Use cases

- Internal-only service names.
- NAS/router hostnames.
- Avoid exposing private names publicly.

### Enable when

Enable once you have more than a few internal services or a DNS filtering resolver.

---

## 6.18 Advertised routes

### Recommended route policy

| Route | Advertise? | Notes |
|---|---:|---|
| `192.168.1.0/24` home LAN | Optional | Only if remote LAN access needed |
| Docker bridge networks | No | Avoid exposing container internals to tailnet |
| Management VLAN | Optional | Admin-only ACL |
| IoT VLAN | Usually no | Minimize risk |
| NAS VLAN | Optional | Admin/backup ACL only |
| `0.0.0.0/0` exit node | Optional | Exit-node mode |
| `::/0` IPv6 exit node | Optional | Only if IPv6 configured correctly |

---

## 6.19 Policy file management

Store ACL policy as code:

```text
infra/tailscale/
  policy.hujson
  README.md
  examples/
  changelog.md
```

Workflow:

1. Edit policy in Git.
2. Run formatter/validator if available.
3. Peer review.
4. Apply through Tailscale admin UI or API.
5. Record policy version and date.
6. Test access with admin and non-admin device.

---

## 6.20 Multiple exit nodes

### Diagram

```text
Remote Device
   +-- Exit Node A: PiKVM at home
   +-- Exit Node B: NUC at home
   +-- Exit Node C: VPS
```

### Strategy

- Use PiKVM as optional low-throughput exit node.
- Use NUC/mini PC as preferred home exit node later.
- Use VPS as emergency remote exit node if desired.
- Name nodes clearly: `exit-home-pikvm`, `exit-home-nuc`, `exit-vps-01`.
- Restrict exit node usage by ACL.

---

## 6.21 Remote administration workflows

### Normal remote admin

```text
1. Connect laptop to Tailscale.
2. SSH to `pikvm-prod`.
3. Check service status.
4. Pull repo changes.
5. Run deploy script or approved CI deployment.
6. Verify health endpoints.
```

### Public outage triage

```text
1. Confirm Tailscale connection.
2. SSH to host.
3. Check cloudflared status.
4. Check Traefik status.
5. Check DNS/tunnel route.
6. Run smoke tests from host and external network.
```

### Lost Cloudflare access

```text
1. Use Tailscale SSH.
2. Access Traefik/dashboard privately if configured.
3. Inspect tunnel logs.
4. Temporarily use Tailscale Serve for admin-only tool if needed.
5. Avoid exposing direct ports.
```

---

## 6.22 Emergency recovery access

Required break-glass paths:

1. **Local PiKVM console path** for direct management.
2. **Tailscale SSH path** for remote admin.
3. **OpenSSH fallback** restricted to local LAN/Tailscale.
4. **Offline backup copy** of secrets recovery key.
5. **Printed or offline runbook** for restoring from backup.
6. **Secondary admin device** authorized in Tailscale.
7. **Recovery USB/SD image procedure** for PiKVM host.

---

---

# 7. Docker Network Design

## 7.1 Required Docker networks

| Network | Type | Purpose | Internet-facing? |
|---|---|---|---:|
| `proxy` | external bridge | Traefik attaches to routable services | Indirectly |
| `public` | bridge | Public apps behind Traefik | Via Traefik only |
| `private` | internal bridge | Private app backend traffic | No |
| `management` | internal bridge | Admin tools and control services | No |
| `monitoring` | internal bridge | Metrics/logging/alerting | No |
| `database` | internal bridge | DB/cache/message queues | No |
| `shared` | bridge/internal depending on use | Shared utilities | Usually no |
| `backup` | internal bridge | Backup jobs and repository services | No |
| `security` | internal bridge | CrowdSec, auth helpers, socket proxy | No |

## 7.2 Docker network diagram

```text
                         +--------------------+
Cloudflare Tunnel ------>|      Traefik       |
                         | networks: proxy    |
                         +---------+----------+
                                   |
              +--------------------+--------------------+
              v                    v                    v
        +----------+         +----------+         +------------+
        | public   |         | mgmt     |         | monitoring |
        | apps     |         | dashboards|        | Grafana    |
        +----+-----+         +----+-----+         +-----+------+
             |                    |                     |
             v                    v                     v
        +----------+         +----------+         +------------+
        | database |         | security |         | logging    |
        | app DBs  |         | auth/WAF |         | Loki       |
        +----------+         +----------+         +------------+

Rules:
- Traefik reaches only services explicitly attached to `proxy`.
- Public apps attach to `public` and optionally `database`.
- Databases never attach to `proxy`.
- Management services should prefer Tailscale/private access.
- Monitoring can scrape app exporters through controlled network membership.
```

## 7.3 Which containers belong where

| Service type | Networks |
|---|---|
| Traefik | `proxy`, optionally `monitoring` for metrics |
| cloudflared | `proxy` only |
| Public web app | `proxy`, `public`, maybe app-specific DB network |
| API app | `proxy`, `public`, `database` if needed |
| Postgres/MariaDB | `database` only |
| Redis | `database` or app-specific private network only |
| Authelia/Authentik | `proxy`, `security`, `database` |
| CrowdSec | `security`, maybe `proxy` log access |
| Grafana | `proxy` if public/protected, `monitoring` |
| Prometheus | `monitoring` |
| Loki | `monitoring` |
| Promtail/Alloy | `monitoring`, host log mounts |
| cAdvisor | `monitoring`, read-only Docker mounts |
| Node Exporter | host network or `monitoring` |
| Uptime Kuma | `proxy` optional, `monitoring` |
| Backup job | `backup`, volume mounts read-only where possible |
| Portainer | Prefer Tailscale only; if proxied, `proxy` + `management` |

## 7.4 Networks that should never communicate directly

| Source | Destination | Reason |
|---|---|---|
| `public` | `management` | A compromised public app must not reach admin tools |
| `public` | all databases | Only specific app-to-DB paths should exist |
| `database` | `proxy` | Databases must never be routable from ingress |
| `monitoring` | `database` | Monitoring should scrape exporters, not DB internals, unless explicitly needed |
| `backup` | `proxy` | Backup jobs should not expose web endpoints |
| `security` | `database` | Only auth/security services that require DB should connect |

## 7.5 Isolation benefits

- Limits lateral movement after compromise.
- Makes service dependencies visible.
- Simplifies firewall and troubleshooting.
- Reduces accidental exposure through Traefik labels.
- Makes future migration to Kubernetes NetworkPolicies or Nomad network stanzas easier.

---

---

# 8. Reverse Proxy Architecture: Traefik

## 8.1 Role of Traefik

Traefik is the internal ingress controller. Cloudflare delivers public traffic to Traefik through an outbound tunnel. Traefik performs service routing, TLS handling, middleware enforcement, security headers, rate limiting, authentication handoff, and observability.

## 8.2 Reverse proxy diagram

```text
Internet Client
   |
   v
Cloudflare DNS / Edge
   |
   v
Cloudflare Tunnel
   |
   v
cloudflared container
   |
   v
Traefik entrypoints
   +-- websecure :443 internal only
   +-- traefik dashboard private/protected
   +-- metrics endpoint internal only
        |
        +-- Router: app.example.com
        |      +-- Middleware chain
        |      |      +-- security headers
        |      |      +-- rate limit
        |      |      +-- compression
        |      |      +-- auth where required
        |      +-- Service: app container
        |
        +-- Router: grafana.example.com
        |      +-- auth middleware
        |      +-- Service: grafana
        |
        +-- Router: dashboard.example.com
               +-- IP allowlist or Tailscale-only
               +-- auth middleware
               +-- Traefik API dashboard
```

## 8.3 Routing design

Use Docker labels for application routes and file provider for shared middlewares and critical dynamic config.

### Recommended route naming

```text
traefik.http.routers.<service>.rule=Host(`service.example.com`)
traefik.http.routers.<service>.entrypoints=websecure
traefik.http.routers.<service>.tls=true
traefik.http.routers.<service>.middlewares=secure-headers@file,rate-limit@file,auth@file
traefik.http.services.<service>.loadbalancer.server.port=8080
```

### Route categories

| Category | Exposure | Auth |
|---|---|---|
| Public websites | Public | Optional depending on app |
| Public APIs | Public | App auth + rate limit |
| Admin dashboards | Private or strongly protected | Mandatory |
| Monitoring | Prefer private/Tailscale; if public, strong auth | Mandatory |
| Webhooks | Public but restricted | Secret validation + rate limit |

## 8.4 TLS design

Because Cloudflare Tunnel terminates public edge HTTPS and forwards to the origin tunnel, there are several TLS options.

Recommended:

1. Use HTTPS at Cloudflare edge.
2. Use HTTPS from cloudflared to Traefik if possible.
3. Use Traefik certificates for origin-side encryption.
4. Use wildcard certificate for `*.example.com` generated through DNS-01 challenge.
5. Store ACME data securely with restricted permissions.

### Wildcard certificates

Use Traefik ACME DNS-01 with Cloudflare DNS token if you are comfortable storing a scoped API token locally. Otherwise use a Cloudflare Origin Certificate or internal CA.

Security requirements:

- Use a Cloudflare API token scoped only to zone DNS edit if DNS-01 is used.
- Store token with SOPS + age.
- Restrict `acme.json` to `0600`.
- Back up certificates and ACME state.

## 8.5 Authentication

Recommended authentication layers:

| Layer | Tool | Purpose |
|---|---|---|
| Cloudflare Access optional | Cloudflare free tier if desired | Edge identity gate, not required |
| Traefik ForwardAuth | Authelia or Authentik | Self-hosted app SSO/MFA |
| App-native auth | App itself | Domain-specific authorization |
| Tailscale ACL | Tailscale | Private admin path |

Recommended free self-hosted auth:

- **Authelia** for lightweight forward-auth, MFA, OIDC in newer versions.
- **Authentik** for richer identity provider features, heavier footprint.

For PiKVM V4, start with Authelia because it is lighter.

## 8.6 Security headers

Shared middleware should include:

- `Strict-Transport-Security`
- `X-Frame-Options` or CSP frame restrictions
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy`
- `Permissions-Policy`
- `Content-Security-Policy` where app compatible
- `X-XSS-Protection` only for legacy compatibility if desired

Do not blindly enforce a strict CSP globally on all apps; many self-hosted apps need app-specific CSP.

## 8.7 Rate limiting

Use default rate limiting for public services:

- General websites: moderate rate limits.
- APIs: stricter rate limits.
- Login paths: strict limits.
- Webhooks: low burst and source validation.

Complement with CrowdSec and Cloudflare rate controls where available free.

## 8.8 Dashboard protection

Traefik dashboard must never be anonymously public.

Acceptable patterns:

1. Tailscale-only access, no public DNS route.
2. Public route behind Authelia MFA and IP/Tailscale allowlist.
3. Local SSH tunnel only.

Recommended: Tailscale-only or Authelia + Tailscale allowlist.

## 8.9 Dynamic configuration

Use file provider for:

- middlewares
- TLS options
- reusable security headers
- auth forwarder
- rate limits
- IP allowlists
- error pages

Use Docker labels for:

- per-service routers
- service ports
- service-specific middleware chain

## 8.10 Automatic service discovery

Enable Docker provider with restrictions:

- `exposedByDefault=false`
- Require explicit `traefik.enable=true`
- Require services to join `proxy` network
- Use constraints if needed to route only labeled services
- Avoid exposing containers accidentally

---

---

# 9. Service Design

## 9.1 Public Applications

### Purpose

User-facing websites, APIs, dashboards intentionally published to the internet.

### Security

- Routed only through Cloudflare Tunnel and Traefik.
- Rate limited.
- Security headers.
- Auth where required.
- App containers non-root where possible.
- No direct database exposure.

### Network

- `proxy`
- `public`
- app-specific `database` only if needed

### Dependencies

- Traefik
- cloudflared
- optional Authelia/Authentik
- databases/caches as needed

---

## 9.2 Media Applications

### Purpose

Media management, streaming, downloads, libraries.

Examples:

- Jellyfin
- Navidrome
- Audiobookshelf
- Jellyseerr
- Radarr/Sonarr only if legally and appropriately used

### Security

- Prefer private/Tailscale access for admin interfaces.
- Public streaming only if necessary and strongly authenticated.
- Use dedicated media volumes with restricted permissions.
- Keep download clients isolated from management networks.

### Network

- `private`
- `proxy` only for services intentionally routed
- separate `media` network may be added later

### Dependencies

- NAS/media storage
- backup policy for metadata, not necessarily large media files
- monitoring for disk usage

---

## 9.3 Monitoring

### Purpose

Metrics, dashboards, uptime checks, alerts.

### Components

- Prometheus
- Grafana OSS
- Alertmanager
- Node Exporter
- cAdvisor
- Blackbox Exporter
- Uptime Kuma

### Security

- Prefer Tailscale-only access.
- If public, require Authelia MFA.
- Prometheus and Alertmanager should not be public.
- Grafana admin password stored in SOPS.

### Network

- `monitoring`
- Grafana may also attach to `proxy`

### Dependencies

- Traefik for optional dashboard route
- exporters
- persistent volumes

---

## 9.4 Infrastructure

### Purpose

Core platform services.

Examples:

- Traefik
- cloudflared
- Authelia
- Docker socket proxy
- Watchtower optional notification-only mode
- registry cache optional

### Security

- Minimal privileges.
- No public admin dashboards.
- Socket proxy instead of raw Docker socket.
- Pinned versions.

### Network

- `proxy`
- `security`
- `management`

### Dependencies

- Secrets management
- DNS
- certificates

---

## 9.5 Authentication

### Purpose

Central identity and access control for web applications.

### Recommended start

Authelia + local users or file-backed users database, later LDAP/Authentik if needed.

### Security

- MFA required for admin apps.
- Strong password hashing.
- Session secrets encrypted.
- Disable self-registration unless required.

### Network

- `proxy`
- `security`
- `database` if using Postgres/Redis

### Dependencies

- SMTP optional for notifications/recovery
- Redis optional for sessions
- database optional depending on tool

---

## 9.6 Networking

### Purpose

Private access, DNS, tunnel ingress, routing.

### Components

- Tailscale host daemon
- cloudflared
- AdGuard Home or Pi-hole
- Unbound optional

### Security

- Tailscale ACLs.
- DNS admin UI private only.
- Tunnel credentials encrypted.
- No direct router port forwards.

### Network

- host network for Tailscale
- `proxy` for cloudflared
- DNS may use host or dedicated network depending on LAN integration

---

## 9.7 Utilities

### Purpose

Small supporting services.

Examples:

- homepage/dashboard
- changedetection.io
- ntfy self-hosted
- filebrowser private-only
- vaultwarden if needed

### Security

- Private by default.
- Public only if there is a clear reason.
- Strong auth.

### Network

- `private`
- `proxy` if routed

---

## 9.8 Developer Tools

### Purpose

Self-hosted Git, CI, runners, artifact handling.

Examples:

- Forgejo
- Gitea
- Woodpecker CI
- Act runner / Forgejo runner
- Docker registry mirror

### Security

- CI runner isolated.
- Avoid mounting host Docker socket directly; use rootless or socket proxy where possible.
- Secrets available only to approved jobs.
- Manual deploy approval required.

### Network

- `management`
- `private`
- `proxy` if web UI published

---

## 9.9 Backups

### Purpose

Encrypted backups, retention, verification, restore tests.

### Components

- restic recommended
- BorgBackup alternative
- rclone optional for remote targets
- healthchecks via Uptime Kuma push monitor or self-hosted endpoint

### Security

- Encrypted repositories.
- Separate backup credentials.
- Read-only source mounts where possible.
- Offline copy of encryption password/key.

### Network

- `backup`
- access to NAS/SFTP/local disk target as needed

---

## 9.10 Automation

### Purpose

Scheduled maintenance and operational automation.

Examples:

- systemd timers
- cron containers
- Ansible later
- Renovate self-hosted optional
- Watchtower notification-only mode

### Security

- Automation uses least privilege.
- No automatic production updates without approval.
- Separate deploy key/token.

### Network

- `management`
- `monitoring` for notifications

---

---
