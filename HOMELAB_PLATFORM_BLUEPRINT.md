# Production-Grade Homelab Cloud Platform Blueprint

**Date:** 2026-08-04  
**Target today:** Single PiKVM V4 running Docker + Docker Compose  
**Development workstation:** M3 Mac local development for speed, validation, and iteration  
**Initial CI/CD choice:** GitHub Actions with a separately hosted local M3 Mac self-hosted runner for validation  
**Later deployment target:** laptop target after local satisfaction and CI/CD retargeting  
**Future targets:** Raspberry Pi, Intel NUC, mini PC, NAS, VPS, multi-node Docker, Nomad, Kubernetes  
**Public ingress model:** Internet -> Cloudflare DNS -> Cloudflare Tunnel -> Traefik -> public services  
**Direct exposed inbound ports:** none  
**Primary design principle:** treat the homelab as a miniature production cloud platform, not a simple Docker host.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Core Architecture Principles](#2-core-architecture-principles)
3. [High-Level Architecture Diagram](#3-high-level-architecture-diagram)
4. [Detailed Infrastructure Diagram](#4-detailed-infrastructure-diagram)
5. [Network Diagram](#5-network-diagram)
6. [Tailscale Architecture](#6-tailscale-architecture)
7. [Docker Network Design](#7-docker-network-design)
8. [Reverse Proxy Architecture: Traefik](#8-reverse-proxy-architecture-traefik)
9. [Service Design](#9-service-design)
10. [CI/CD Architecture](#10-cicd-architecture)
11. [Deployment Pipeline](#11-deployment-pipeline)
12. [Rollback Workflow](#12-rollback-workflow)
13. [Backup Architecture](#13-backup-architecture)
14. [Monitoring Architecture](#14-monitoring-architecture)
15. [Logging Architecture](#15-logging-architecture)
16. [Security Architecture](#16-security-architecture)
17. [Secrets Management](#17-secrets-management)
18. [Observability Model](#18-observability-model)
19. [Production Directory Structure](#19-production-directory-structure)
20. [Technology Comparison Tables](#20-technology-comparison-tables)
21. [Recommended Technology Stack](#21-recommended-technology-stack)
22. [Testing Strategy](#22-testing-strategy)
23. [Documentation Standards](#23-documentation-standards)
24. [Future Expansion Roadmap](#24-future-expansion-roadmap)
25. [Disaster Recovery Plan](#25-disaster-recovery-plan)
26. [Complete Implementation Phases](#26-complete-implementation-phases)
27. [Small-Model Session Prompts](#27-small-model-session-prompts)
28. [Risks and Mitigations](#28-risks-and-mitigations)
29. [Final Recommended Architecture](#29-final-recommended-architecture)
30. [Appendix: Operational Checklists](#30-appendix-operational-checklists)
31. [M3 Mac Local Development and LLM Flow Checklist](#31-m3-mac-local-development-and-llm-flow-checklist)
32. [Detailed GitHub Actions CI/CD Design](#32-detailed-github-actions-cicd-design)
33. [Daily Backup and One-Shot Git Checkpoint Restore](#33-daily-backup-and-one-shot-git-checkpoint-restore)

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

# 10. CI/CD Architecture

## 10.1 CI/CD goals

- Free software or free tier only.
- Validate everything before deployment.
- No automatic production deployment without explicit approval.
- Reproducible builds.
- Rollback-ready releases.
- Audit trail in Git.

## 10.2 CI/CD diagram

```text
Developer
   |
   | git commit / push
   v
Git repository
   |
   +-- Pull request checks
   |      +-- lint Markdown/YAML/shell
   |      +-- format check
   |      +-- compose config validation
   |      +-- secret leakage scan
   |      +-- container build
   |      +-- image scan
   |      +-- SBOM generation
   |      +-- integration tests
   |
   +-- Release workflow
          +-- create versioned release artifact
          +-- require manual approval
          +-- deploy through Tailscale SSH or local runner
          +-- health checks
          +-- traffic verification
          +-- rollback on failure
          +-- notify admin
```

## 10.3 Free CI options

### GitHub Actions free tier

Pros:

- Easy to start.
- Good marketplace ecosystem.
- Free for public repositories and limited free minutes for private.
- Manual approval environments available.

Cons:

- SaaS dependency.
- Private repo minutes may be limited.
- Vendor lock-in to workflow syntax.
- Requires secure remote deploy path.

Best use:

- Public or low-volume private repo.
- Initial validation workflow.
- Manual deployments through Tailscale SSH or self-hosted runner.

### Forgejo Actions

Pros:

- Free and open-source.
- Self-hosted Git + Actions-like CI.
- Good GitHub Actions compatibility direction.
- No paid SaaS dependency.

Cons:

- You operate it.
- Runner hardening required.
- Ecosystem smaller than GitHub.

Best use:

- Long-term no-SaaS GitOps-inspired platform.

### Gitea Actions

Pros:

- Mature self-hosted Git server.
- Actions-like workflows.
- Lightweight.

Cons:

- Similar self-hosting burden.
- Compatibility and feature differences vs GitHub.

Best use:

- Simple self-hosted Git + CI.

### Woodpecker CI

Pros:

- FOSS.
- Lightweight.
- Good container-native pipeline model.
- Works with Forgejo/Gitea.

Cons:

- Different pipeline syntax.
- Manual approval patterns may require careful design.

Best use:

- Self-hosted CI with explicit pipeline stages and runners.

### Drone CE

Pros:

- Container-native.
- Historically popular.

Cons:

- Community edition limitations and ecosystem concerns.
- Woodpecker is often preferred as a community fork.

Best use:

- Only if you already know Drone and its constraints.

## 10.4 Recommended CI path

| Stage | Recommendation |
|---|---|
| Day 1 | GitHub Actions if repo is already on GitHub and convenience matters |
| FOSS-first target | Forgejo + Woodpecker CI or Forgejo Actions |
| Runner location | local runner on separate machine if available; PiKVM only if resource use is acceptable |
| Deploy method | Tailscale SSH with locked deploy user, or local runner on host |
| Approval | Manual environment approval or manual `workflow_dispatch` with release tag |

---

# 11. Deployment Pipeline

## 11.1 Complete deployment pipeline diagram

```text
Developer
   |
   v
Git Push / Pull Request
   |
   v
Lint
   |
   v
Formatting Check
   |
   v
YAML Validation
   |
   v
Docker Compose Validation
   |
   v
Secret Validation / Secret Leak Scan
   |
   v
Docker Build
   |
   v
Container Image Scan
   |
   v
SBOM Generation
   |
   v
Integration Tests
   |
   v
Smoke Tests in Staging/Test Compose Project
   |
   v
Generate Versioned Release
   |
   v
Manual Approval Gate
   |
   v
Deploy to Production Host
   |
   v
Health Checks
   |
   v
Traffic Verification through Traefik/Cloudflare/Tailscale
   |
   +-- success --> Notify Success
   |
   +-- failure --> Rollback --> Verify Previous Version --> Notify Failure
```

## 11.2 Pipeline stages

### Stage 1: Developer

Developer changes Compose files, Traefik config, scripts, docs, or app versions.

Required local checks:

- `docker compose config`
- YAML lint
- shellcheck
- markdown lint optional
- secret scan before commit

### Stage 2: Git push

Push to feature branch. Main branch is protected.

Rules:

- Pull request required.
- CI must pass.
- Manual review for production-impacting changes.
- Secrets must never be committed unencrypted.

### Stage 3: Lint

Tools:

- `yamllint`
- `shellcheck`
- `hadolint` for Dockerfiles
- `markdownlint-cli` optional

### Stage 4: Formatting

Tools:

- `prettier` for YAML/Markdown if desired
- `shfmt` for shell scripts
- `.editorconfig`

### Stage 5: YAML validation

Validate all YAML files parse correctly.

Tools:

- `yamllint`
- `yq`
- Python `ruamel.yaml` optional

### Stage 6: Compose validation

Run:

```powershell
Docker compose -f compose\production.yml config
```

For Linux CI:

```bash
docker compose -f compose/production.yml config
```

Validation requirements:

- No missing environment variables.
- Networks declared.
- Volumes declared.
- Health checks present for critical services.
- Restart policies present.
- Images pinned to versions.

### Stage 7: Secret validation

Tools:

- `gitleaks`
- `trufflehog` optional
- `sops --decrypt --extract` checks only in secure CI context

Validate:

- No plaintext secrets.
- Required SOPS files decrypt in authorized environment.
- `.env.example` has non-secret placeholders.
- Secret file permissions are correct after deployment.

### Stage 8: Docker build

Build local custom images if any.

Principles:

- Prefer official images with pinned versions.
- Build only when necessary.
- Use multi-stage builds.
- Generate SBOM for custom images.

### Stage 9: Container scan

Tools:

- Trivy
- Grype
- Docker Scout is not required because FOSS-first design prefers Trivy/Grype.

Policy:

- Critical vulnerabilities fail unless explicitly accepted with expiration.
- High vulnerabilities require review.
- Base images updated through controlled PRs.

### Stage 10: Integration tests

Use test Compose project:

- Start minimal stack.
- Validate Traefik config loads.
- Validate service discovery labels.
- Validate health endpoints.
- Validate network isolation where testable.

### Stage 11: Smoke tests

Examples:

- `GET /healthz`
- Traefik ping endpoint.
- Grafana login page returns expected status.
- Prometheus targets endpoint available internally.
- cloudflared tunnel status healthy.

### Stage 12: Generate release

Release artifact includes:

- Git SHA.
- Compose rendered config.
- Changed files list.
- SBOMs.
- Image tags/digests.
- Migration notes.
- Rollback target.

### Stage 13: Manual approval

Production deployment requires explicit approval.

Acceptable mechanisms:

- GitHub Environments manual approval.
- Forgejo protected environments or manual workflow.
- Woodpecker manual promotion.
- Human runs `deploy.ps1`/`deploy.sh` with release tag.

### Stage 14: Deploy

Deployment steps:

1. Connect to host over Tailscale SSH.
2. Pull repo or release artifact.
3. Decrypt secrets locally on host.
4. Snapshot current config and selected volumes.
5. Render Compose config.
6. Pull new images.
7. Start/update services.
8. Wait for health checks.

### Stage 15: Health checks

Health checks must verify:

- Container health state.
- Expected ports listening internally.
- Traefik routers loaded.
- Public routes return expected HTTP status.
- Private admin routes accessible through Tailscale.
- Monitoring targets are up.

### Stage 16: Traffic verification

Verify through:

- Internal Docker network checks.
- Host checks.
- Tailscale checks.
- Cloudflare public checks.
- Traefik access logs.

### Stage 17: Rollback if failed

Rollback triggers if:

- Critical container unhealthy.
- Public service unavailable beyond threshold.
- Traefik config invalid.
- Database migration failed.
- Health checks fail.

### Stage 18: Notify success/failure

Free notification options:

- Self-hosted ntfy.
- Email through existing SMTP if available.
- Gotify.
- Matrix webhook.
- Uptime Kuma notifications.

---

# 12. Rollback Workflow

## 12.1 Rollback diagram

```text
Deployment Started
   |
   v
Pre-deploy Snapshot
   +-- Compose files
   +-- Config files
   +-- Secret material references
   +-- Image digests
   +-- Critical volumes/database dump
   |
   v
Deploy New Version
   |
   v
Health + Traffic Checks
   |
   +-- Pass --> Mark release successful --> Notify
   |
   +-- Fail
          |
          v
      Stop failed containers
          |
          v
      Restore previous compose/config/secrets
          |
          v
      Restore database/volume snapshot if needed
          |
          v
      Start previous containers
          |
          v
      Verify previous health
          |
          +-- Pass --> Notify rollback success
          +-- Fail --> Escalate emergency runbook
```

## 12.2 Rollback requirements

Before every production deploy:

- Store current Git SHA.
- Store current image digests.
- Render and save current Compose config.
- Snapshot config directories.
- Dump databases before migrations.
- Snapshot or restic-backup critical volumes.
- Record previous secrets version.

## 12.3 Rollback strategy by component

| Component | Rollback method |
|---|---|
| Compose config | Checkout previous Git SHA or release artifact |
| Images | Pull/run previous image digests |
| Secrets | Restore previous encrypted file or decrypted runtime file from secure snapshot |
| Traefik config | Restore previous dynamic/static config and reload |
| Database schema | Prefer backward-compatible migrations; otherwise restore dump |
| Volumes | Restore restic snapshot for affected service |
| Certificates | Restore ACME/cert files if corrupted |

## 12.4 Automatic rollback rules

Automatic rollback can be safe for stateless services. For stateful services, rollback must be conservative.

Recommended rules:

- **Stateless app failure:** automatic rollback allowed.
- **Traefik failure:** automatic rollback allowed.
- **cloudflared failure:** automatic rollback allowed.
- **Database migration failure before commit:** automatic rollback allowed.
- **Database migration completed and incompatible:** require manual recovery unless dump restore is explicitly approved.
- **Secret rotation failure:** automatic rollback to previous secret if still valid.

---

# 13. Backup Architecture

## 13.1 Backup goals

- Encrypted by default.
- Automated schedule.
- Versioned retention.
- Verified regularly.
- Restore-tested.
- Covers config, volumes, secrets, databases, certs, logs where useful.
- No paid backup SaaS required.

## 13.2 Backup architecture diagram

```text
PiKVM V4 Host
   |
   +-- Compose repository
   +-- Config directories
   +-- SOPS-encrypted secrets
   +-- Docker volumes
   +-- Database dumps
   +-- Traefik ACME/certs
   +-- Selected logs
          |
          v
Backup Orchestrator
   +-- pre-backup hooks
   |      +-- pause/flush if needed
   |      +-- database dumps
   +-- restic/Borg encrypted backup
   +-- prune retention
   +-- check repository
   +-- restore test sample
   +-- notify status
          |
          v
Backup Targets
   +-- local USB SSD
   +-- NAS over SSH/SFTP
   +-- second homelab node
   +-- offline rotated disk
```

## 13.3 Recommended backup software

Primary recommendation: **restic**.

Why:

- Free and open-source.
- Strong encryption.
- Supports local, SFTP, REST server, S3-compatible, rclone backends.
- Good deduplication.
- Easy restore.

Alternative: **BorgBackup**.

Why:

- Very mature.
- Excellent deduplication.
- Great over SSH.

Optional helper: **rclone** for moving encrypted restic repositories to additional self-hosted targets.

## 13.4 What to back up

| Data | Backup method | Frequency | Notes |
|---|---|---|---|
| Git repo / Compose files | Git + restic | Every deploy + daily | Git is not enough if remote unavailable |
| Config directories | restic | Daily + pre-deploy | Include Traefik, Authelia, monitoring configs |
| SOPS encrypted secrets | Git + restic | On change + daily | Safe to store encrypted copies |
| Decrypted runtime secrets | Avoid if possible | If backed up, encrypted restic only | Prefer regenerating from SOPS |
| Docker volumes | restic | Daily | Stop/quiesce if app requires consistency |
| Databases | logical dump + restic | Daily + pre-deploy | `pg_dump`, `mysqldump`, SQLite copy with lock |
| Certificates/ACME | restic | Daily + on renew | Restrict restore permissions |
| Logs | Loki retention + optional restic | Depends | Keep only useful retention |
| CI artifacts/releases | Git release + restic | On release | Needed for rollback |

## 13.5 Backup schedule

Recommended baseline:

| Schedule | Task |
|---|---|
| Hourly | Lightweight config backup for critical configs if changes frequent |
| Daily | Full restic backup of configs, volumes, DB dumps |
| Weekly | Repository check + sample restore |
| Monthly | Full disaster recovery restore test to temporary directory/host |
| Before deploy | Pre-deploy snapshot and DB dump |
| Before upgrade | Full backup + restore validation |

## 13.6 Retention policy

Example restic retention:

- Keep hourly: 24
- Keep daily: 14
- Keep weekly: 8
- Keep monthly: 12
- Keep yearly: 3 if storage allows

Adjust for storage size.

## 13.7 Backup verification

Backups are not real until restored.

Verification tasks:

- `restic check` weekly.
- Restore random file weekly.
- Restore critical service config monthly.
- Restore database dump to temporary container monthly.
- Perform full platform restore drill quarterly.

## 13.8 Restore testing

Restore test process:

```text
1. Create temporary restore directory.
2. Restore latest snapshot.
3. Verify expected files exist.
4. Validate Compose config from restored files.
5. Start one non-critical service using restored volume/config.
6. Restore database dump into temporary DB.
7. Run smoke tests.
8. Delete temporary restore environment.
9. Record result in docs/restore-tests.md.
```

---

# 14. Monitoring Architecture

## 14.1 Monitoring goals

- Detect failures before users do.
- Measure host resource pressure.
- Monitor container health.
- Monitor public and private endpoints.
- Alert on backup failure, disk usage, certificate expiration, tunnel failure.
- Keep enough retention for troubleshooting without exhausting PiKVM storage.

## 14.2 Monitoring architecture diagram

```text
Targets / Exporters
   +-- Node Exporter          host CPU/RAM/disk/network
   +-- cAdvisor               container CPU/RAM/restarts
   +-- Traefik metrics        routers/services/status
   +-- Blackbox Exporter      HTTP/TCP/DNS checks
   +-- cloudflared metrics    tunnel health if enabled
   +-- restic backup metrics  backup age/status
   +-- app /health endpoints
          |
          v
Prometheus
   +-- scrape configs
   +-- alert rules
   +-- retention policy
          |
          +-- Alertmanager --> ntfy/Gotify/email/Matrix
          |
          v
Grafana OSS
   +-- Host dashboard
   +-- Docker dashboard
   +-- Traefik dashboard
   +-- Backup dashboard
   +-- Cloudflare tunnel dashboard
   +-- SLO/service dashboard

Uptime Kuma
   +-- Public endpoint checks
   +-- Private Tailscale checks
   +-- Push monitors for backups/deploys
   +-- Status page optional
```

## 14.3 Recommended monitoring stack

| Component | Purpose |
|---|---|
| Prometheus | Metrics collection and alert rules |
| Grafana OSS | Dashboards and visualizations |
| Alertmanager | Alert routing/dedup/silence |
| Node Exporter | Host metrics |
| cAdvisor | Container metrics |
| Blackbox Exporter | Endpoint probing |
| Uptime Kuma | Simple uptime/status checks |
| Traefik metrics | Ingress visibility |
| Loki + Promtail/Alloy | Logs, covered in logging section |

## 14.4 Dashboards

Minimum dashboards:

1. **Host Overview**
   - CPU usage
   - load average
   - memory usage
   - disk usage
   - filesystem read-only state
   - network throughput
   - temperature if available

2. **Docker Overview**
   - container count
   - unhealthy containers
   - restart count
   - per-container CPU/memory
   - image versions

3. **Traefik Ingress**
   - request rate
   - error rate
   - latency percentiles
   - routers/services up
   - 4xx/5xx by service

4. **Cloudflare Tunnel**
   - tunnel process up
   - connector count
   - reconnects
   - edge location if available

5. **Backups**
   - last successful backup time
   - backup duration
   - repository size
   - prune/check result
   - restore-test age

6. **Security**
   - CrowdSec decisions
   - failed login counts
   - auth failures
   - suspicious IPs

7. **Service SLO**
   - availability
   - latency
   - error rate
   - saturation

## 14.5 Alerts

Critical alerts:

| Alert | Severity | Condition |
|---|---|---|
| Host down | critical | Node exporter unreachable |
| Disk almost full | critical | >90% for 10 min |
| Disk filling | warning | >80% for 30 min |
| Memory pressure | warning | sustained high memory / swap |
| Container unhealthy | critical | critical service unhealthy |
| Container restart loop | warning/critical | restarts > threshold |
| Traefik high 5xx | critical | 5xx rate above threshold |
| Public service down | critical | blackbox/Uptime Kuma failure |
| Cloudflare tunnel down | critical | cloudflared unhealthy |
| Backup failed | critical | no successful backup in 26h |
| Restore test stale | warning | no restore test in 35 days |
| Certificate expiring | warning/critical | <21 days / <7 days |
| Secret decryption failure | critical | deploy cannot decrypt required secrets |
| High auth failures | warning | failed logins spike |

## 14.6 Retention

For PiKVM V4, start conservative:

| Data | Retention |
|---|---|
| Prometheus metrics | 15-30 days locally |
| Loki logs | 7-14 days locally |
| Uptime Kuma history | 30-90 days depending storage |
| Backup logs | 90 days compressed |
| Security logs | 30-90 days depending risk/storage |

Future NAS/NUC can increase retention.

---

# 15. Logging Architecture

## 15.1 Logging goals

- Centralize container, system, proxy, auth, deploy, backup, and security logs.
- Keep local retention controlled.
- Make incidents diagnosable.
- Avoid filling disk.
- Protect sensitive data.

## 15.2 Logging architecture diagram

```text
Log Sources
   +-- Docker container stdout/stderr
   +-- Traefik access/error logs
   +-- cloudflared logs
   +-- Authelia/auth logs
   +-- systemd journal
   +-- SSH/auth logs
   +-- deployment logs
   +-- backup logs
   +-- security tools logs
          |
          v
Promtail or Grafana Alloy
   +-- labels: service, environment, host, stack
   +-- redaction where possible
   +-- shipping pipeline
          |
          v
Loki
   +-- retention policy
   +-- indexes
   +-- object/local storage
          |
          v
Grafana Explore / Dashboards / Alerts
```

## 15.3 Central logging stack

Recommended:

- Loki for log storage.
- Promtail or Grafana Alloy for collection.
- Grafana for searching and dashboards.

Promtail is stable but Grafana Alloy is the newer collector direction. For simplicity on PiKVM, Promtail is acceptable; for long-term consistency, consider Alloy.

## 15.4 Docker log rotation

Configure Docker daemon log rotation:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Rationale:

- Prevents container logs from filling disk.
- Loki receives logs for search.
- Local logs remain bounded.

## 15.5 Log retention

| Log type | Retention |
|---|---|
| Container logs in Docker json files | 3 files x 10 MB each by default |
| Loki app logs | 7-14 days on PiKVM |
| Security/auth logs | 30-90 days if storage allows |
| Deployment logs | 90 days or per release |
| Backup logs | 90 days plus latest summary |
| Traefik access logs | 7-30 days depending traffic |

## 15.6 Sensitive log handling

- Do not log secrets or tokens.
- Mask Authorization headers.
- Be careful with query strings.
- Avoid debug logging in production except temporarily.
- Restrict Loki/Grafana access.
- Back up only logs needed for compliance/troubleshooting.

---

# 16. Security Architecture

## 16.1 Security architecture diagram

```text
Public Internet
   |
   v
Cloudflare Edge
   +-- DNS proxy/tunnel route
   +-- optional WAF/rules/free protections
   +-- no direct home IP exposure
   |
   v
Cloudflare Tunnel
   +-- outbound-only connector
   |
   v
Traefik
   +-- explicit routers only
   +-- TLS
   +-- security headers
   +-- rate limiting
   +-- auth middleware
   +-- CrowdSec bouncer optional
   +-- dashboard protected
   |
   v
Docker Services
   +-- non-root users
   +-- read-only root FS where possible
   +-- dropped capabilities
   +-- no-new-privileges
   +-- isolated networks
   +-- pinned images
   +-- health checks
   |
   v
Host
   +-- firewall deny inbound except Tailscale/local needs
   +-- SSH restricted
   +-- automatic security updates with controlled reboot policy
   +-- fail2ban/CrowdSec where applicable
   +-- encrypted secrets
   +-- monitored backups
```

## 16.2 Least privilege

Apply least privilege everywhere:

- Users get only required access.
- CI deploy user can deploy only platform files.
- Containers run as non-root where supported.
- Volumes mounted read-only unless write is required.
- Docker socket not exposed directly.
- Tailscale ACLs restrict admin paths.
- Cloudflare tokens scoped narrowly.

## 16.3 Docker security

Recommended Compose security defaults where compatible:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true
tmpfs:
  - /tmp
restart: unless-stopped
```

Not every image supports read-only root filesystems or all capabilities dropped. Document exceptions per service.

## 16.4 Read-only containers

Use read-only root filesystem for:

- Static web apps.
- Exporters.
- Simple APIs.
- Reverse proxy if configured correctly.

Avoid or test carefully for:

- Databases.
- Apps that write cache to root.
- Apps requiring package/runtime writes.

## 16.5 Capability dropping

Default:

```yaml
cap_drop:
  - ALL
```

Add back only required capabilities. Examples:

| Capability | When needed |
|---|---|
| `NET_BIND_SERVICE` | Bind low ports inside container, usually avoid by using high internal ports |
| `NET_ADMIN` | VPN/network tools, avoid unless necessary |
| `CHOWN` | Some init scripts, avoid where possible |

## 16.6 Non-root containers

Prefer images that support `user:` or non-root by default.

For custom apps:

- Create non-root user in Dockerfile.
- Use writable directories owned by app user.
- Avoid privileged containers.

## 16.7 Network isolation

- Use dedicated networks per trust zone.
- Do not attach every service to `proxy`.
- Databases never attach to ingress network.
- Admin tools private by default.
- Monitoring can reach targets but targets should not reach monitoring unless necessary.

## 16.8 Authentication and authorization

- Public apps with sensitive data must require authentication.
- Admin dashboards require MFA.
- Prefer Authelia for forward auth.
- Use app-native role-based access where available.
- Use Tailscale ACLs for admin network authorization.

## 16.9 Secret management

- Use SOPS + age for secrets in Git.
- Decrypt only on trusted host or secure CI runner.
- Do not commit plaintext `.env` files.
- Use `.env.example` for documentation.
- Rotate tokens periodically.

## 16.10 Automatic updates

Recommendation:

- Enable OS security updates automatically if stable for your OS.
- Do not automatically update production containers without review.
- Use Renovate or Dependabot-like PRs for image updates.
- Use Watchtower in notification-only mode, not auto-update mode, for production.

## 16.11 Firewall

Host firewall policy:

- Deny inbound by default.
- Allow established/related.
- Allow Tailscale interface.
- Allow LAN SSH only if needed and restricted.
- Do not expose Traefik ports to LAN unless intentional.
- No WAN port forwards.

## 16.12 fail2ban and CrowdSec

### fail2ban

Useful for:

- SSH logs.
- Local auth logs.
- Simple brute-force blocking.

Less useful when:

- No direct public SSH exists.
- Public traffic source IP handling is behind Cloudflare unless real IPs are restored.

### CrowdSec

Useful for:

- Traefik log parsing.
- Community blocklists/decisions.
- Bouncer integration with Traefik.

Recommendation:

- Start with Traefik logs + CrowdSec once public apps exist.
- Ensure Cloudflare real client IP headers are handled correctly.

## 16.13 Container image scanning

Use:

- Trivy for vulnerabilities and misconfigurations.
- Grype as optional second scanner.
- Syft for SBOM.

Policy:

- Critical CVEs fail builds unless documented exception.
- Exceptions require expiration date.
- Pin image versions and preferably digests for critical services.

## 16.14 SBOM generation

Generate SBOM for custom images and important deployments:

- Syft SPDX or CycloneDX output.
- Store SBOM as release artifact.
- Use Grype/Trivy against SBOM where useful.

---

# 17. Secrets Management

## 17.1 Comparison

| Tool | Free/FOSS | Best for | Pros | Cons | Recommendation |
|---|---:|---|---|---|---|
| Environment variables | Yes | Simple local runtime | Easy, Compose-native | Easy to leak, weak lifecycle | Use only for non-sensitive or generated runtime from encrypted source |
| Docker Secrets | Yes, but best in Swarm | Secret files in containers | Better than env vars | Compose support differs; not full secret manager | Good if using Swarm; limited for plain Compose |
| SOPS | Yes | Encrypted secrets in Git | GitOps-friendly, supports age/GPG/KMS | Requires workflow discipline | Primary recommendation |
| age | Yes | Encryption backend | Simple modern key encryption | Key custody needed | Use with SOPS |
| Vault Community | Yes | Dynamic secrets, enterprise workflows | Powerful, audit, leases | Heavy, operational complexity | Future option, not day-one on PiKVM |
| Mozilla SOPS + age + direnv | Yes | Developer workflow | Excellent balance | Must avoid accidental export/logging | Recommended with care |

## 17.2 Best practice recommendation

Use **SOPS + age** as the default.

Store:

```text
secrets/
  production/
    cloudflare.sops.yaml
    traefik.sops.yaml
    authelia.sops.yaml
    grafana.sops.yaml
    restic.sops.yaml
  staging/
    ...
```

Runtime flow:

```text
Encrypted secrets in Git
   |
   v
Authorized deploy host decrypts with age key
   |
   v
Temporary runtime env files generated with strict permissions
   |
   v
Docker Compose starts services
   |
   v
Runtime env files cleaned or kept protected depending service needs
```

## 17.3 Key custody

- Store age private key on the production host with `0600` permissions.
- Keep offline encrypted backup of age private key.
- Keep printed recovery instructions, not printed secrets unless absolutely necessary and physically secured.
- Use separate keys for production and staging.
- Rotate keys if a device is lost.

## 17.4 What not to do

- Do not commit plaintext `.env.production`.
- Do not paste secrets into CI logs.
- Do not mount the whole secrets folder into every container.
- Do not reuse Cloudflare global API keys; use scoped tokens.
- Do not store restic password only on the machine being backed up.

---

# 18. Observability Model

## 18.1 Four pillars

| Pillar | Tooling | Purpose |
|---|---|---|
| Metrics | Prometheus, exporters, Grafana | Quantitative system state |
| Logs | Loki, Promtail/Alloy, Grafana | Event/context investigation |
| Traces | OpenTelemetry optional | Request flow across services |
| Health | Docker health checks, Uptime Kuma, Blackbox | Availability and readiness |

## 18.2 Metrics

Metrics answer:

- Is it up?
- Is it slow?
- Is it saturated?
- Is it erroring?
- Is capacity running out?

## 18.3 Logs

Logs answer:

- What happened?
- Which user/IP/service was involved?
- What changed before failure?
- Are there auth/security anomalies?

## 18.4 Traces

For a small homelab, traces are optional. Add OpenTelemetry later if you run custom apps or multiple microservices.

## 18.5 Health

Every service should define:

- Liveness: container process is alive.
- Readiness: service can receive traffic.
- Dependency health: DB/cache reachable if required.
- External availability: public route returns expected response.

## 18.6 Alerting

Alerts should be actionable:

- Include service name.
- Include symptom.
- Include likely cause.
- Include runbook link.
- Avoid noisy alerts.
- Use warning/critical severity.

## 18.7 Status pages

Use Uptime Kuma status pages for:

- personal visibility.
- family/internal users.
- simple public status page if desired.

Protect admin access; public status page should not reveal sensitive infrastructure details.

---

# 19. Production Directory Structure

## 19.1 Directory tree

```text
homelab-platform/
  README.md
  CHANGELOG.md
  LICENSE
  .editorconfig
  .gitignore
  .sops.yaml
  Makefile

  docs/
    architecture/
      overview.md
      network.md
      security.md
      tailscale.md
      traefik.md
      backups.md
      monitoring.md
      logging.md
      disaster-recovery.md
      scaling-roadmap.md
    runbooks/
      deploy.md
      rollback.md
      restore.md
      tunnel-outage.md
      tailscale-recovery.md
      disk-full.md
      certificate-expiry.md
      database-restore.md
    decisions/
      ADR-0001-platform-principles.md
      ADR-0002-cloudflare-tunnel-traefik.md
      ADR-0003-sops-age-secrets.md
      ADR-0004-restic-backups.md
    diagrams/
      architecture.ascii.md
      network.ascii.md
      tailscale-modes.ascii.md
    troubleshooting/
      common-failures.md
      docker.md
      traefik.md
      dns.md
      tailscale.md

  infra/
    host/
      README.md
      sysctl.d/
      nftables/
      ufw/
      systemd/
        backup.service
        backup.timer
        maintenance.service
        maintenance.timer
      docker/
        daemon.json
    tailscale/
      README.md
      policy.hujson
      examples/
    cloudflare/
      README.md
      tunnel/
        config.yml.template
      dns/
        records.md
    security/
      README.md
      crowdsec/
      fail2ban/
      hardening-checklist.md

  compose/
    production.yml
    staging.yml
    networks.yml
    volumes.yml
    override.example.yml
    profiles/
      public.yml
      monitoring.yml
      backups.yml
      media.yml
      devtools.yml

  stacks/
    proxy/
      README.md
      compose.yml
      traefik/
        static.yml
        dynamic/
          middlewares.yml
          tls.yml
          security-headers.yml
          rate-limits.yml
      cloudflared/
        config.yml.template
    auth/
      README.md
      compose.yml
      authelia/
        configuration.yml.template
    monitoring/
      README.md
      compose.yml
      prometheus/
        prometheus.yml
        rules/
      grafana/
        provisioning/
          dashboards/
          datasources/
      alertmanager/
        alertmanager.yml.template
      uptime-kuma/
    logging/
      README.md
      compose.yml
      loki/
        loki.yml
      promtail/
        promtail.yml
    backups/
      README.md
      compose.yml
      restic/
        backup.sh
        restore.sh
        check.sh
        forget-prune.sh
    dns/
      README.md
      compose.yml
      adguardhome/
      pihole/
      unbound/
    apps/
      example-public-app/
        README.md
        compose.yml
        config/
      example-private-app/
        README.md
        compose.yml
    media/
      README.md
      compose.yml
    devtools/
      README.md
      compose.yml
      forgejo/
      woodpecker/

  configs/
    README.md
    common/
    production/
    staging/
    templates/

  secrets/
    README.md
    production/
      cloudflare.sops.yaml
      traefik.sops.yaml
      authelia.sops.yaml
      grafana.sops.yaml
      restic.sops.yaml
    staging/
      example.sops.yaml

  scripts/
    README.md
    bootstrap/
      00-check-host.sh
      01-install-docker.sh
      02-create-networks.sh
      03-install-tailscale.sh
      04-setup-firewall.sh
    deploy/
      deploy.sh
      preflight.sh
      healthcheck.sh
      verify-traffic.sh
      rollback.sh
    backup/
      backup.sh
      restore.sh
      restore-test.sh
    validate/
      validate-compose.sh
      validate-traefik.sh
      validate-cloudflared.sh
      validate-secrets.sh
      validate-networks.sh
      validate-permissions.sh
    maintenance/
      update-os.sh
      prune-docker.sh
      rotate-logs.sh

  ci/
    README.md
    github-actions/
      validate.yml
      release.yml
      deploy.yml
    forgejo-actions/
      validate.yml
      deploy.yml
    woodpecker/
      .woodpecker.yml
    scripts/
      ci-lint.sh
      ci-test.sh
      ci-scan.sh

  templates/
    service/
      README.md.template
      compose.yml.template
      env.example.template
      healthcheck.sh.template
    traefik/
      labels.public.yml.template
      labels.private.yml.template
    docs/
      runbook.template.md
      adr.template.md
      service-readme.template.md

  tests/
    README.md
    compose/
      test-compose-config.sh
    traefik/
      test-routers.sh
      test-middlewares.sh
    cloudflare/
      test-tunnel-config.sh
    networking/
      test-network-isolation.sh
    backups/
      test-restore.sh
    security/
      test-no-plaintext-secrets.sh
      test-permissions.sh

  releases/
    README.md
    .gitkeep
```

## 19.2 Directory purposes

| Directory | Purpose |
|---|---|
| `docs/` | Human documentation, architecture, runbooks, ADRs |
| `infra/` | Host-level and external platform configuration |
| `compose/` | Top-level Compose entrypoints and shared definitions |
| `stacks/` | Modular service stacks by domain |
| `configs/` | Environment-specific non-secret configuration |
| `secrets/` | SOPS-encrypted secret files only |
| `scripts/` | Bootstrap, deploy, validate, backup, maintenance automation |
| `ci/` | CI workflow definitions and helper scripts |
| `templates/` | Reusable templates for new services/docs |
| `tests/` | Automated validation scripts |
| `releases/` | Generated release metadata, not bulky artifacts |

---

# 20. Technology Comparison Tables

## 20.1 Reverse proxy

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Traefik | Docker-native, labels, ACME, middleware, metrics | Dynamic config complexity | Recommended |
| Caddy | Very simple TLS, great UX | Docker discovery less rich without plugins | Good alternative |
| Nginx Proxy Manager | Easy UI | Less GitOps-native, UI-driven drift | Avoid for this goal |
| HAProxy | Very powerful/stable | More manual config | Good for advanced LB later |

## 20.2 Private network / VPN

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Tailscale | Easy WireGuard mesh, ACLs, MagicDNS, SSH | Coordination service dependency | Recommended per requirements |
| Headscale | FOSS Tailscale control server | Operate yourself, feature differences | Future lock-in reduction option |
| WireGuard raw | Fully FOSS, simple | Manual keys/routes | Good fallback |
| Netbird | FOSS option | Extra platform operation | Evaluate later |

## 20.3 CI/CD

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| GitHub Actions | Easy, strong ecosystem | SaaS dependency/free tier limits | Good starter |
| Forgejo Actions | Self-hosted, FOSS | Operate runners | Long-term recommended |
| Gitea Actions | Lightweight self-hosted | Similar ops burden | Good option |
| Woodpecker CI | Lightweight, FOSS | Different syntax | Strong self-hosted recommendation |
| Drone CE | Container-native | CE concerns | Not first choice |

## 20.4 Monitoring

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Prometheus | Standard, powerful | Pull config/retention tuning | Recommended |
| Grafana OSS | Excellent dashboards | Needs auth/security | Recommended |
| Uptime Kuma | Very easy uptime checks | Not full metrics system | Recommended supplement |
| Netdata | Quick host observability | Less GitOps-focused | Optional |
| Zabbix | Enterprise monitoring | Heavier | Future option |

## 20.5 Logging

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| Loki | Good with Grafana, efficient labels | Query model differs from full text search | Recommended |
| Elasticsearch/OpenSearch | Powerful search | Heavy for PiKVM | Avoid initially |
| Graylog | Good UI | Heavy | Avoid initially |
| File logs only | Simple | Poor centralized troubleshooting | Insufficient |

## 20.6 Backups

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| restic | Encrypted, simple, many backends | Forget/prune/check discipline needed | Recommended |
| BorgBackup | Excellent dedupe, mature | Best over SSH/local, fewer backend types | Strong alternative |
| Kopia | Nice features/UI | More moving parts | Optional |
| rsync only | Simple | No built-in encryption/versioning | Not sufficient alone |

## 20.7 Secrets

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| SOPS + age | GitOps-friendly, FOSS | Key management required | Recommended |
| Docker Secrets | Better runtime secret mount | Best with Swarm | Optional/limited Compose |
| Vault Community | Powerful | Heavy operational burden | Future only |
| Plain env files | Easy | Risky | Avoid for real secrets |

## 20.8 DNS filtering

| Tool | Pros | Cons | Verdict |
|---|---|---|---|
| AdGuard Home | Modern UI, policies | Additional service dependency | Recommended if new |
| Pi-hole | Mature community | Less modern policy model | Good alternative |
| Unbound | Recursive resolver | Not ad filtering by itself | Pair with either |

---

# 21. Recommended Technology Stack

## 21.1 Day-one stack

| Layer | Tool |
|---|---|
| Runtime | Docker CE + Docker Compose plugin |
| Public edge | Cloudflare DNS + Cloudflare Tunnel |
| Reverse proxy | Traefik |
| Private access | Tailscale |
| Secrets | SOPS + age |
| Monitoring | Prometheus, Grafana OSS, Node Exporter, cAdvisor, Alertmanager |
| Uptime | Uptime Kuma |
| Logging | Loki + Promtail/Alloy |
| Backups | restic |
| Security scanning | Trivy + Syft |
| Auth | Authelia |
| DNS filtering | AdGuard Home or Pi-hole, optional Unbound |
| Notifications | ntfy or Gotify |
| CI starter | GitHub Actions or local scripts |
| CI long-term | Forgejo + Woodpecker CI or Forgejo Actions |

## 21.2 Why this stack

- Compose is appropriate for a single PiKVM today.
- Traefik scales naturally from Compose to Swarm/Kubernetes-style ingress concepts.
- Tailscale gives secure private admin without exposing ports.
- SOPS + age makes secrets GitOps-compatible without heavy infrastructure.
- Prometheus/Grafana/Loki are standard and portable.
- restic gives encrypted backups with simple restore.
- Forgejo/Woodpecker provide a future no-SaaS workflow.

---

# 22. Testing Strategy

## 22.1 Required automated tests

| Area | Test |
|---|---|
| Docker Compose | `docker compose config` for every stack/profile |
| Traefik configuration | Static/dynamic config syntax, routers, middlewares |
| Cloudflare Tunnel | YAML syntax, ingress rules, target availability |
| Health endpoints | HTTP checks for `/healthz`, Traefik ping, app health |
| Networking | Verify expected containers share networks and forbidden pairs do not |
| DNS | Resolve public domain, internal MagicDNS, split DNS records |
| Volumes | Verify required volumes exist and mount permissions work |
| Permissions | Check secret files `0600`, ACME `0600`, scripts executable |
| Container startup | Start test stack and wait for healthy states |
| Restart policy | Assert critical services use `unless-stopped` or equivalent |
| Environment variables | Required env vars present, no placeholder secrets in prod |
| Certificates | Cert exists, not expired, SAN matches route |
| Secrets | No plaintext secrets, SOPS decrypt works in authorized environment |

## 22.2 Test environments

| Environment | Purpose |
|---|---|
| local validation | Fast syntax checks before commit |
| CI validation | Repeatable checks on PR |
| staging Compose project | Start subset of stack with separate project name |
| production smoke | Post-deploy real checks |
| restore test | Validate backups independently |

## 22.3 Compose tests

Examples:

```bash
docker compose -f compose/production.yml config >/tmp/rendered-compose.yml
docker compose -f stacks/proxy/compose.yml config >/tmp/proxy-compose.yml
```

Validate:

- no missing variables
- no invalid YAML
- no accidental host port exposure except explicitly documented local-only ports
- critical health checks exist
- networks are declared

## 22.4 Traefik tests

Validate:

- dynamic config parses
- middlewares exist
- routers reference existing middlewares
- dashboard route is protected
- `exposedByDefault=false`
- metrics endpoint is not public

## 22.5 Cloudflare Tunnel tests

Validate:

- tunnel config YAML parses
- ingress hostnames match expected public routes
- final rule returns 404 or safe default
- cloudflared container can resolve/reach Traefik

## 22.6 Networking tests

Automate checks like:

- Database container is not attached to `proxy`.
- Public app cannot reach management container.
- Traefik can reach only labeled public services.
- Prometheus can reach exporters.

## 22.7 DNS tests

Check:

- `service.example.com` resolves publicly to Cloudflare.
- Tailscale MagicDNS resolves `pikvm-prod`.
- Split DNS resolves internal names.
- AdGuard/Pi-hole upstream works.

## 22.8 Permissions tests

Check:

- `acme.json` is `0600`.
- SOPS age key is `0600`.
- secret runtime env files are `0600`.
- backup repository credentials are not world-readable.
- scripts are executable and owned correctly.

---

# 23. Documentation Standards

## 23.1 Required documentation types

| Doc type | Location | Purpose |
|---|---|---|
| Architecture overview | `docs/architecture/overview.md` | Big picture |
| Network diagram | `docs/architecture/network.md` | Network/security model |
| Service README | each stack folder | How service works and is operated |
| ADR | `docs/decisions/` | Record major decisions |
| Runbook | `docs/runbooks/` | Operational procedures |
| Troubleshooting | `docs/troubleshooting/` | Known failures and fixes |
| Disaster recovery | `docs/architecture/disaster-recovery.md` | Restore platform |
| Upgrade guide | per major service | Safe update process |
| Rollback guide | `docs/runbooks/rollback.md` | Restore previous release |

## 23.2 Architecture diagrams

Use ASCII diagrams in Markdown first. Optional future tools:

- Mermaid
- PlantUML
- Graphviz
- diagrams-as-code

All diagrams should include:

- data flow
- trust boundaries
- network names
- external dependencies
- failure domains

## 23.3 Service README template

Each service should document:

```text
# Service Name

## Purpose
## Owner
## Exposure
## URLs
## Networks
## Volumes
## Secrets
## Dependencies
## Health checks
## Backup/restore
## Upgrade procedure
## Rollback procedure
## Troubleshooting
## Security notes
```

## 23.4 Runbook standards

Each runbook should include:

- Symptoms.
- Impact.
- Immediate checks.
- Step-by-step remediation.
- Rollback/escape path.
- Verification.
- Post-incident follow-up.

## 23.5 Decision records

Use ADRs for decisions such as:

- Why Cloudflare Tunnel + Traefik.
- Why SOPS + age.
- Why restic.
- Why Authelia vs Authentik.
- Why Compose before Kubernetes/Nomad.

---

# 24. Future Expansion Roadmap

## 24.1 One node -> multi-node roadmap

### Stage A: Single PiKVM V4

- Docker Compose.
- Cloudflare Tunnel.
- Traefik.
- Tailscale.
- Monitoring/logging/backups.

### Stage B: Add NAS

- Move backup target to NAS.
- Move media storage to NAS.
- Add NAS monitoring.
- Add NAS as Tailscale node.
- Optional second DNS resolver.

### Stage C: Add Intel NUC / mini PC

- Move heavier apps to NUC.
- Keep PiKVM for KVM/admin/infrastructure or lightweight services.
- Add second cloudflared connector.
- Add second Traefik instance or keep one ingress node.
- Use Tailscale subnet routing on both.

### Stage D: Multi-host Docker

Options:

- Continue separate Compose per host with shared Git repo.
- Use Docker contexts over SSH.
- Use Ansible for orchestration.
- Consider Docker Swarm if simple multi-node service scheduling is desired.

### Stage E: Nomad migration

Nomad is a strong intermediate step:

- Lightweight compared to Kubernetes.
- Good for mixed workloads.
- Consul optional for service discovery.
- Traefik can integrate.

### Stage F: Kubernetes migration

Kubernetes is appropriate if:

- You need declarative scheduling.
- You want Helm/Kustomize ecosystem.
- You have at least 3 stable nodes for HA control plane or accept non-HA k3s.
- You are ready for storage/network complexity.

Suggested distro:

- k3s for lightweight homelab.
- Talos Linux for immutable cluster later.

## 24.2 High availability expansion

| Component | Single-node today | HA future |
|---|---|---|
| Cloudflare Tunnel | one connector | multiple connectors on different hosts |
| Traefik | one instance | active/active or active/passive ingress nodes |
| DNS filtering | one AdGuard/Pi-hole | two resolvers |
| Monitoring | one Prometheus | remote write or second monitoring node |
| Logs | one Loki | NAS/object storage backend or second Loki |
| Backups | local + USB/NAS | 3-2-1 with offsite self-hosted target |
| Databases | local volumes | replicated DB or app-specific HA |
| Tailscale subnet router | PiKVM | two route advertisers |
| Exit node | optional PiKVM | NUC + VPS alternatives |

## 24.3 Load balancing

Near-term:

- Cloudflare Tunnel can route to one or more local services.
- Traefik can load balance between multiple container instances on a host.

Future:

- Multiple Traefik nodes.
- Keepalived/VRRP on LAN if using direct LAN VIP.
- Cloudflare Load Balancing is paid, so avoid relying on it.
- DNS failover can be manual or scripted.

## 24.4 Distributed storage

Avoid distributed storage too early.

Options later:

| Tool | Use case | Notes |
|---|---|---|
| NFS from NAS | Simple shared storage | Easy but single NAS dependency |
| Samba | Media/user shares | Not ideal for app databases |
| Syncthing | Config/file sync | Not database-safe |
| Longhorn | Kubernetes block storage | Needs multiple nodes/disks |
| Ceph | Serious distributed storage | Heavy for small homelab |
| MinIO | S3-compatible object storage | Good backup/artifact target |

## 24.5 Multiple PiKVMs

If adding multiple PiKVMs:

- Each joins Tailscale with tag `tag:pikvm`.
- Keep PiKVM device management private.
- Do not expose PiKVM web UI publicly unless strongly justified.
- Use naming: `pikvm-rack-01`, `pikvm-rack-02`.
- Monitor reachability and certificate status.

## 24.6 Multiple Cloudflare tunnels

Patterns:

1. **Single tunnel, multiple connectors**
   - Same tunnel token on multiple hosts.
   - Cloudflare balances connector availability.

2. **One tunnel per environment**
   - `prod-tunnel`, `staging-tunnel`.
   - Cleaner separation.

3. **One tunnel per site**
   - home, VPS, remote lab.

Recommendation:

- Start with one production tunnel.
- Add a second connector on NUC/NAS later.
- Use separate staging tunnel if staging becomes public.

---

# 25. Disaster Recovery Plan

## 25.1 Disaster scenarios

| Scenario | Recovery approach |
|---|---|
| Single container failure | restart, rollback service |
| Bad deployment | automatic/manual rollback |
| Traefik config broken | restore previous proxy stack config |
| Cloudflare tunnel broken | Tailscale admin path, restore tunnel config/token |
| Host disk failure | rebuild host, restore repo/secrets/volumes |
| Lost age key | use offline backup key; if unavailable rotate all secrets |
| Database corruption | restore latest valid dump/snapshot |
| Compromised service | isolate, rotate secrets, restore clean version, review logs |
| Home internet outage | Tailscale unavailable from outside unless DERP/alternate path; use local recovery or VPS future |
| PiKVM hardware failure | restore to laptop/NUC/Raspberry Pi using backups |

## 25.2 Recovery time objectives

Suggested targets:

| Service class | RTO | RPO |
|---|---:|---:|
| Ingress/proxy | 30 minutes | config last commit |
| Monitoring | 1 hour | 24 hours acceptable |
| Public critical app | 1 hour | latest backup/pre-deploy snapshot |
| Media apps | 24 hours | 24 hours |
| Backups metadata | 4 hours | latest repository state |
| DNS filtering | 1 hour | latest config backup |

## 25.3 Full host rebuild process

```text
1. Prepare replacement host: PiKVM/laptop/NUC.
2. Install OS and update packages.
3. Install Docker CE and Compose plugin.
4. Install Tailscale and join tailnet with correct tags.
5. Configure firewall.
6. Clone homelab-platform repo.
7. Restore age private key from offline backup.
8. Decrypt required secrets.
9. Restore configs and Docker volumes from restic.
10. Restore database dumps.
11. Recreate Docker networks.
12. Start core stacks: proxy, tunnel, auth.
13. Start monitoring/logging/backups.
14. Start applications.
15. Verify Tailscale access.
16. Verify Cloudflare Tunnel route.
17. Run production smoke tests.
18. Document incident and recovery time.
```

## 25.4 Minimum emergency kit

Keep offline:

- This blueprint.
- Current runbooks.
- Backup repository password.
- age private key backup.
- Cloudflare recovery instructions.
- Tailscale recovery/admin instructions.
- List of critical domains and services.
- Latest known-good release tag.

---

# 26. Complete Implementation Phases

These phases are designed so each phase can be completed by a smaller model or in a focused implementation session.

## Phase 0: Planning and inventory

### Goal

Create the source-of-truth repo structure and document current hardware, domains, IP ranges, and desired services.

### Tasks

1. Create `homelab-platform` repository.
2. Add base directory structure.
3. Add `README.md` with goals and assumptions.
4. Document hardware inventory.
5. Document current network ranges.
6. Choose production domain and internal domain.
7. Choose naming convention.
8. Create ADR for platform principles.

### Deliverables

- Repo skeleton.
- Inventory document.
- Network assumptions document.
- Initial ADRs.

### Done criteria

- Repository has all top-level directories.
- README states no direct exposed ports.
- Hardware and domain assumptions are documented.

---

## Phase 1: Host baseline hardening

### Goal

Prepare PiKVM V4 or laptop host as a stable Docker platform.

### Tasks

1. Update OS.
2. Install Docker CE and Compose plugin.
3. Configure Docker log rotation.
4. Create deployment user.
5. Configure SSH restrictions.
6. Configure firewall deny-by-default.
7. Add base system monitoring packages.
8. Add systemd maintenance timers.
9. Document host bootstrap.

### Deliverables

- `infra/host/docker/daemon.json`
- firewall config
- bootstrap scripts
- host hardening runbook

### Done criteria

- Docker works.
- Compose works.
- Firewall blocks unwanted inbound access.
- Logs rotate.
- Host can be administered safely.

---

## Phase 2: Tailscale private administration

### Goal

Establish private admin plane.

### Tasks

1. Install Tailscale on host OS.
2. Join tailnet with stable hostname.
3. Enable MagicDNS.
4. Define device tags.
5. Draft ACL policy.
6. Enable Tailscale SSH or restrict OpenSSH to Tailscale.
7. Test admin access from laptop and phone.
8. Document normal and emergency workflows.

### Deliverables

- `infra/tailscale/policy.hujson`
- Tailscale runbook
- emergency access runbook

### Done criteria

- Admin can SSH over Tailscale.
- Non-admin access is denied by ACL.
- MagicDNS resolves host.

---

## Phase 3: Docker networks and base Compose framework

### Goal

Create modular network and Compose foundation.

### Tasks

1. Define external Docker networks.
2. Create `compose/networks.yml`.
3. Create stack template.
4. Add validation script for networks.
5. Document network purpose and allowed communication.

### Deliverables

- network definitions
- service template
- network docs

### Done criteria

- Required networks exist.
- Compose config validates.
- No service can be exposed by default.

---

## Phase 4: Traefik reverse proxy

### Goal

Deploy Traefik as internal ingress controller.

### Tasks

1. Create proxy stack.
2. Configure Traefik static config.
3. Configure Docker provider with `exposedByDefault=false`.
4. Add dynamic middleware files.
5. Add security headers.
6. Add rate limits.
7. Protect dashboard.
8. Enable metrics endpoint internally.
9. Add test service route.
10. Validate routing.

### Deliverables

- `stacks/proxy/compose.yml`
- Traefik config
- middleware config
- proxy runbook

### Done criteria

- Traefik starts.
- Test service routes only when explicitly labeled.
- Dashboard is protected/private.
- Metrics are available internally.

---

## Phase 5: Cloudflare Tunnel public ingress

### Goal

Connect public DNS to Traefik without exposing ports.

### Tasks

1. Create Cloudflare tunnel.
2. Store tunnel credentials securely.
3. Configure cloudflared stack.
4. Route `*.example.com` or selected hosts to Traefik.
5. Ensure final ingress rule is safe default.
6. Test public route.
7. Document tunnel recovery.

### Deliverables

- cloudflared config template
- encrypted tunnel secrets
- DNS/tunnel docs

### Done criteria

- Public test route works through Cloudflare Tunnel.
- No router ports are forwarded.
- Tunnel credentials are not plaintext in Git.

---

## Phase 6: Secrets management with SOPS + age

### Goal

Make secrets GitOps-compatible and secure.

### Tasks

1. Install SOPS and age.
2. Generate production age key.
3. Create `.sops.yaml`.
4. Create encrypted secret files.
5. Add decrypt/render script.
6. Add secret validation CI check.
7. Document key backup and rotation.

### Deliverables

- `.sops.yaml`
- `secrets/production/*.sops.yaml`
- validation script
- secrets runbook

### Done criteria

- Secrets decrypt only on authorized host.
- No plaintext secrets in Git.
- Recovery key is backed up offline.

---

## Phase 7: Authentication layer

### Goal

Protect admin and sensitive web apps.

### Tasks

1. Deploy Authelia.
2. Configure users, password hashing, sessions.
3. Configure MFA.
4. Add Traefik forward-auth middleware.
5. Protect Traefik dashboard/Grafana/Uptime Kuma.
6. Test login and denial paths.
7. Document account recovery.

### Deliverables

- auth stack
- Authelia config template
- encrypted auth secrets
- auth runbook

### Done criteria

- Sensitive route requires auth.
- MFA works for admin.
- Failed access is logged.

---

## Phase 8: Monitoring stack

### Goal

Deploy metrics, dashboards, and alerts.

### Tasks

1. Deploy Prometheus.
2. Deploy Grafana.
3. Deploy Node Exporter.
4. Deploy cAdvisor.
5. Deploy Alertmanager.
6. Add Traefik metrics scrape.
7. Add dashboards.
8. Add baseline alert rules.
9. Test alert delivery.

### Deliverables

- monitoring stack
- Prometheus configs
- Grafana provisioning
- alert rules
- monitoring runbook

### Done criteria

- Host/container metrics visible.
- Alerts fire in test mode.
- Dashboards load.

---

## Phase 9: Logging stack

### Goal

Centralize logs with bounded retention.

### Tasks

1. Deploy Loki.
2. Deploy Promtail or Alloy.
3. Collect Docker logs.
4. Collect Traefik logs.
5. Collect system logs if appropriate.
6. Add log retention.
7. Create Grafana log dashboards.
8. Test searching incident logs.

### Deliverables

- logging stack
- Loki config
- collector config
- log dashboard
- logging runbook

### Done criteria

- Container logs searchable in Grafana.
- Traefik logs searchable.
- Retention is bounded.

---

## Phase 10: Backup and restore

### Goal

Automate encrypted backups and prove restores work.

### Tasks

1. Install/configure restic.
2. Create backup repository.
3. Encrypt backup credentials with SOPS.
4. Write backup script.
5. Write database dump hooks.
6. Write forget/prune script.
7. Write restore script.
8. Add systemd timer.
9. Add backup monitoring.
10. Perform restore test.

### Deliverables

- backup scripts
- systemd timer
- backup runbook
- restore runbook
- restore test log

### Done criteria

- Backup completes automatically.
- Backup failure alerts.
- Restore test succeeds.

---

## Phase 11: Security controls

### Goal

Add runtime hardening, scanning, and threat controls.

### Tasks

1. Add Compose security defaults.
2. Document exceptions.
3. Add Trivy scans.
4. Add Syft SBOM generation.
5. Deploy CrowdSec for Traefik logs.
6. Configure fail2ban if SSH logs warrant it.
7. Add permission validation.
8. Add security dashboard/alerts.

### Deliverables

- security configs
- scan workflows
- SBOM artifacts
- security runbook

### Done criteria

- Critical images scanned.
- Security defaults applied where compatible.
- Public ingress has rate/security protections.

---

## Phase 12: CI validation

### Goal

Validate repo changes before merge.

### Tasks

1. Add CI workflow.
2. Add YAML lint.
3. Add shellcheck.
4. Add Compose validation.
5. Add secret scanning.
6. Add Trivy config scan.
7. Add test stack startup if runner supports Docker.
8. Publish CI status.

### Deliverables

- CI workflow files
- CI scripts
- contribution guide

### Done criteria

- Pull request fails on invalid Compose/YAML/secrets.
- Main branch protected by CI.

---

## Phase 13: Manual deployment pipeline

### Goal

Create controlled production deployment with manual approval.

### Tasks

1. Write deploy script.
2. Write preflight checks.
3. Write release metadata generation.
4. Add manual approval workflow.
5. Add health checks.
6. Add traffic verification.
7. Add notifications.
8. Document deployment runbook.

### Deliverables

- deploy scripts
- CI deploy workflow
- release metadata format
- deployment runbook

### Done criteria

- Nothing deploys automatically to production.
- Manual approved deploy works.
- Health and traffic checks run after deploy.

---

## Phase 14: Rollback automation

### Goal

Restore previous known-good state on failed deploy.

### Tasks

1. Capture pre-deploy state.
2. Store previous image digests.
3. Snapshot config/secrets refs.
4. Add rollback script.
5. Integrate rollback into deploy failure path.
6. Test rollback with a deliberately bad deployment.
7. Document rollback runbook.

### Deliverables

- rollback script
- rollback tests
- rollback runbook

### Done criteria

- Failed stateless deployment automatically rolls back.
- Previous service health is verified.
- Admin is notified.

---

## Phase 15: DNS filtering and split DNS

### Goal

Add optional DNS filtering for tailnet and/or LAN.

### Tasks

1. Choose AdGuard Home or Pi-hole.
2. Deploy DNS stack.
3. Configure upstream resolvers.
4. Configure blocklists.
5. Configure Tailscale DNS/split DNS.
6. Test normal DNS and blocked domains.
7. Document failure/recovery.

### Deliverables

- DNS stack
- DNS docs
- Tailscale split DNS config notes

### Done criteria

- Tailnet clients resolve internal names.
- DNS filtering works.
- DNS outage recovery is documented.

---

## Phase 16: Advanced Tailscale modes

### Goal

Enable only the Tailscale modes actually needed.

### Tasks

1. Evaluate need for subnet router.
2. Enable subnet routes if needed.
3. Evaluate need for exit node.
4. Enable exit node only for trusted admins if needed.
5. Configure ACL restrictions.
6. Test MagicDNS, SSH, split DNS.
7. Document mode-specific operations.

### Deliverables

- updated Tailscale policy
- Tailscale modes runbook
- route test results

### Done criteria

- Enabled modes have clear justification.
- ACLs restrict route/exit usage.
- Emergency recovery workflow tested.

---

## Phase 17: Add first real application

### Goal

Deploy one production app using the platform standards.

### Tasks

1. Create service folder from template.
2. Define Compose service.
3. Attach only required networks.
4. Add Traefik labels.
5. Add health check.
6. Add secrets via SOPS.
7. Add backup rules.
8. Add monitoring/logging labels.
9. Add service README.
10. Deploy through manual pipeline.

### Deliverables

- app stack
- service docs
- monitoring/backup integration

### Done criteria

- App works publicly or privately as intended.
- Health checks and backups work.
- Rollback path exists.

---

## Phase 18: Documentation completion

### Goal

Make platform self-documenting.

### Tasks

1. Finish architecture docs.
2. Finish network docs.
3. Finish security docs.
4. Finish runbooks.
5. Add troubleshooting guides.
6. Add upgrade guides.
7. Add disaster recovery guide.
8. Review docs for accuracy against actual config.

### Deliverables

- complete docs tree
- diagrams
- runbooks

### Done criteria

- A new admin can understand and recover platform from docs.
- Docs match actual files.

---

## Phase 19: Multi-node preparation

### Goal

Prepare architecture for future nodes without redesign.

### Tasks

1. Add host inventory model.
2. Add naming/tagging conventions.
3. Add per-host Compose profiles.
4. Add backup target abstraction.
5. Add second Tailscale node plan.
6. Add second tunnel connector plan.
7. Document migration paths to Nomad/k3s.

### Deliverables

- multi-node docs
- host inventory template
- scaling ADR

### Done criteria

- Adding a NUC/NAS requires adding inventory and stack assignment, not redesign.

---

## Phase 20: Quarterly operational review

### Goal

Keep platform healthy over time.

### Tasks

1. Review backups and restore tests.
2. Review alerts/noise.
3. Review security updates.
4. Review image vulnerability reports.
5. Review Tailscale ACLs.
6. Review exposed routes.
7. Review disk capacity.
8. Update documentation.

### Deliverables

- quarterly review report
- action items
- updated risks

### Done criteria

- Platform remains secure, documented, and recoverable.

---

# 27. Small-Model Session Prompts

Use these prompts one session at a time with a smaller model such as DeepSeek V4 Flash. Each session is intentionally scoped. Tell the model to modify files directly if it has tools, or output only the requested files if not.

## Global instruction to prepend to every small-model session

```text
You are implementing a production-grade homelab platform repository. Use free and open-source software wherever possible. Optimize for stability, security, maintainability, observability, and reliability. Do not expose router ports directly. Public access must be Cloudflare DNS -> Cloudflare Tunnel -> Traefik -> services. Private administration must use Tailscale. Keep changes modular, documented, and GitOps-inspired. Do not commit plaintext secrets. Use placeholders and SOPS-encrypted file templates for secrets.

Mandatory session behavior:
- Start every session with a question gate. Ask any clarifying questions needed to avoid guessing, especially for accounts, domains, tokens, API keys, credentials, DNS zones, Cloudflare Tunnel details, Tailscale settings, Git/CI access, SMTP/notification settings, backup repository credentials, and proxy requirements.
- Never paste, hardcode, commit, or print real secrets. If a real token/key/password is required, stop and ask the user to provide it through a secure local mechanism such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate proxy, LAN proxy, or reverse-proxy/domain settings are required before writing network-dependent configuration.
- Verify each major step with commands, file reads, linters, config validation, tests, or explicit inspection before continuing.
- Do not mark a session complete until every Done criterion is verified with evidence.
- Do not start or recommend the next session until the user gives an explicit green signal.
```

---

## Session 1 Prompt: Create repository skeleton

```text
Task: Create the initial homelab-platform repository skeleton.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create the directory tree for docs, infra, compose, stacks, configs, secrets, scripts, ci, templates, tests, releases.
2. Create README.md explaining the platform goals:
   - free software where possible
   - production-grade homelab
   - single PiKVM V4 today
   - expandable to more nodes later
   - public ingress through Cloudflare Tunnel and Traefik only
   - private admin through Tailscale
3. Create .gitignore that excludes decrypted secrets, runtime env files, logs, local backups, and generated artifacts.
4. Create .editorconfig.
5. Create docs/decisions/ADR-0001-platform-principles.md.
6. Do not create real secrets.

Deliverables:
- Complete folder structure.
- README.md.
- .gitignore.
- .editorconfig.
- ADR-0001.

Done criteria:
- Repo structure exists.
- No plaintext secret files exist.
- README is clear enough for a new admin.
```

---

## Session 2 Prompt: Host bootstrap and Docker baseline

```text
Task: Add host bootstrap files for a PiKVM V4 or laptop Docker host.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create infra/host/docker/daemon.json with Docker json-file log rotation.
2. Create scripts/bootstrap/00-check-host.sh to verify Linux, Docker availability, CPU arch, disk space, memory, and required commands.
3. Create scripts/bootstrap/01-install-docker.sh as a documented script skeleton with safe checks and comments.
4. Create scripts/bootstrap/04-setup-firewall.sh as a documented deny-by-default firewall skeleton using ufw or nftables, with Tailscale allowance notes.
5. Create docs/runbooks/host-bootstrap.md explaining how to prepare the host.
6. Do not make destructive assumptions.

Deliverables:
- Docker daemon config.
- Bootstrap scripts.
- Host bootstrap runbook.

Done criteria:
- Scripts are idempotent or clearly documented.
- Docker logs are bounded.
- Firewall plan blocks inbound by default and permits Tailscale/admin access.
```

---

## Session 3 Prompt: Tailscale baseline design files

```text
Task: Add Tailscale baseline configuration and documentation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create infra/tailscale/README.md.
2. Create infra/tailscale/policy.hujson example with groups, tags, ACLs, and SSH policy placeholders.
3. Include tags: tag:prod, tag:server, tag:pikvm, tag:monitoring, tag:ci, tag:backup, tag:exit-node, tag:subnet-router.
4. Document MagicDNS, Tailscale SSH, normal node, subnet router, exit node, split DNS, and emergency recovery.
5. Create docs/runbooks/tailscale-recovery.md.
6. Make clear that normal node + MagicDNS is day-one; exit node/subnet router are optional and ACL-restricted.

Deliverables:
- Tailscale policy example.
- Tailscale docs.
- Recovery runbook.

Done criteria:
- Policy is least-privilege oriented.
- Admin access is documented.
- Optional modes are not enabled blindly.
```

---

## Session 4 Prompt: Docker networks and Compose foundation

```text
Task: Create Docker network and Compose foundation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create compose/networks.yml defining proxy, public, private, management, monitoring, database, shared, backup, security networks.
2. Mark sensitive networks internal where appropriate.
3. Create scripts/bootstrap/02-create-networks.sh to create external networks idempotently.
4. Create docs/architecture/network.md explaining every network, which containers belong where, and forbidden communication paths.
5. Create templates/service/compose.yml.template for a new service with security defaults, healthcheck placeholder, and Traefik labels disabled by default.

Deliverables:
- compose/networks.yml.
- network creation script.
- network architecture docs.
- service template.

Done criteria:
- Network names match platform standard.
- Database and management networks are not exposed by default.
- Template does not expose services accidentally.
```

---

## Session 5 Prompt: Traefik proxy stack

```text
Task: Create the Traefik reverse proxy stack.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/proxy/compose.yml with Traefik service attached to proxy and monitoring networks.
2. Configure Docker provider with exposedByDefault=false.
3. Create stacks/proxy/traefik/static.yml.
4. Create dynamic config files for middlewares, security headers, TLS options, and rate limits.
5. Add protected dashboard pattern; dashboard must not be anonymously public.
6. Enable ping and metrics internally.
7. Create docs/architecture/traefik.md and docs/runbooks/traefik.md.
8. Use placeholders for domain names and secrets.

Deliverables:
- Proxy Compose stack.
- Traefik static/dynamic configs.
- Documentation and runbook.

Done criteria:
- Traefik discovery is explicit only.
- Dashboard is protected/private.
- Middleware chain includes security headers and rate limit.
```

---

## Session 6 Prompt: Cloudflare Tunnel stack

```text
Task: Add Cloudflare Tunnel stack and documentation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Add cloudflared service to stacks/proxy/compose.yml or a separate stacks/proxy/cloudflared compose fragment.
2. Create stacks/proxy/cloudflared/config.yml.template.
3. Route example hostnames to Traefik.
4. Include safe default final rule returning 404.
5. Create infra/cloudflare/README.md explaining DNS records, tunnel setup, token handling, and recovery.
6. Create scripts/validate/validate-cloudflared.sh to parse/check config presence.
7. Do not include real tunnel credentials.

Deliverables:
- cloudflared config template.
- docs for Cloudflare DNS/Tunnel.
- validation script.

Done criteria:
- Public ingress path is Cloudflare Tunnel -> Traefik.
- No direct port exposure is suggested.
- Credentials are referenced as secrets only.
```

---

## Session 7 Prompt: SOPS + age secrets framework

```text
Task: Add SOPS + age secret management framework.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create .sops.yaml with placeholder age recipient.
2. Create secrets/README.md explaining no plaintext secrets, key custody, decryption flow, and rotation.
3. Create sample encrypted-file templates using placeholder values but do not fake real encrypted blobs unless SOPS is actually run.
4. Create scripts/validate/validate-secrets.sh to check for plaintext secret anti-patterns and required files.
5. Create scripts/deploy/render-secrets.sh skeleton that decrypts SOPS files into runtime env files with 0600 permissions.
6. Create docs/runbooks/secrets.md.

Deliverables:
- .sops.yaml.
- secrets docs.
- validation/render scripts.
- runbook.

Done criteria:
- No real secret values are committed.
- Workflow is clear and secure.
- Runtime secret files are generated, not manually edited.
```

---

## Session 8 Prompt: Authelia authentication stack

```text
Task: Add Authelia authentication stack for Traefik ForwardAuth.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/auth/compose.yml for Authelia with minimal dependencies.
2. Create Authelia configuration template with placeholders.
3. Add Traefik dynamic middleware for forward-auth integration.
4. Store secrets as SOPS placeholders only.
5. Create docs/architecture/authentication.md and docs/runbooks/authentication.md.
6. Include MFA requirement for admin services.
7. Document account recovery and lockout procedure.

Deliverables:
- Auth stack.
- Config templates.
- Traefik middleware update.
- Auth docs/runbook.

Done criteria:
- Admin dashboards can be protected by forward-auth.
- No plaintext auth secrets.
- MFA and recovery are documented.
```

---

## Session 9 Prompt: Monitoring stack

```text
Task: Add Prometheus/Grafana/Alertmanager monitoring stack.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/monitoring/compose.yml with Prometheus, Grafana OSS, Alertmanager, Node Exporter, cAdvisor, Blackbox Exporter, and Uptime Kuma if appropriate.
2. Create Prometheus scrape config for host, cAdvisor, Traefik, and blackbox checks.
3. Create baseline alert rules for disk, host down, container down, Traefik 5xx, backup stale, certificate expiry.
4. Create Grafana provisioning for datasource and dashboard folder placeholders.
5. Create docs/architecture/monitoring.md and docs/runbooks/monitoring.md.

Deliverables:
- Monitoring Compose stack.
- Prometheus config and rules.
- Grafana provisioning.
- Docs/runbook.

Done criteria:
- Metrics stack is modular.
- Critical alerts are defined.
- Dashboards can be provisioned as code.
```

---

## Session 10 Prompt: Logging stack

```text
Task: Add centralized logging stack.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/logging/compose.yml with Loki and Promtail or Grafana Alloy.
2. Configure collection of Docker container logs and Traefik logs.
3. Add Loki retention settings suitable for small disk.
4. Create Grafana datasource provisioning update if needed.
5. Create docs/architecture/logging.md and docs/runbooks/logging.md.
6. Document Docker daemon log rotation and sensitive log handling.

Deliverables:
- Logging stack.
- Collector config.
- Loki config.
- Docs/runbook.

Done criteria:
- Logs are centralized and searchable.
- Retention is bounded.
- Sensitive data handling is documented.
```

---

## Session 11 Prompt: Backup and restore framework

```text
Task: Add restic-based backup and restore framework.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/backups or scripts/backup with backup.sh, restore.sh, check.sh, forget-prune.sh, restore-test.sh.
2. Include backup of Compose repo, configs, SOPS-encrypted secrets, Docker volumes, database dumps, ACME/certs, selected logs.
3. Use restic with encrypted repository and SOPS-managed credentials.
4. Add systemd service/timer examples.
5. Add Uptime Kuma push monitor or notification hook placeholder.
6. Create docs/architecture/backups.md, docs/runbooks/backup.md, docs/runbooks/restore.md.
7. Include retention policy and restore-test procedure.

Deliverables:
- Backup scripts.
- Systemd timer examples.
- Backup/restore docs.

Done criteria:
- Backups are encrypted.
- Restore testing is documented and scripted.
- Backup failure can alert.
```

---

## Session 12 Prompt: Security scanning and hardening

```text
Task: Add security scanning and hardening framework.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create scripts/validate/validate-permissions.sh for secret files, acme.json, age keys, scripts.
2. Create scripts/validate/validate-compose-security.sh checking for risky Compose patterns: privileged containers, raw Docker socket mounts, missing restart policies, host networking, missing no-new-privileges where expected.
3. Add ci/scripts/ci-scan.sh using Trivy and Syft if available.
4. Create infra/security/README.md documenting least privilege, container hardening, CrowdSec, fail2ban, firewall, update policy.
5. Add docs/architecture/security.md.

Deliverables:
- Security validation scripts.
- Scan script.
- Security docs.

Done criteria:
- Risky Compose patterns are detectable.
- Image scanning and SBOM generation are planned.
- Security exceptions must be documented.
```

---

## Session 13 Prompt: CI validation workflows

```text
Task: Add free CI validation workflows.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create ci/github-actions/validate.yml for YAML lint, shellcheck, compose config, secret scan, Trivy config scan.
2. Create ci/woodpecker/.woodpecker.yml equivalent or documented skeleton.
3. Create ci/README.md comparing GitHub Actions, Forgejo Actions, Gitea Actions, Woodpecker CI, Drone CE.
4. Ensure CI only validates by default and does not deploy production automatically.
5. Add manual workflow dispatch skeleton for release/deploy with explicit approval notes.

Deliverables:
- CI workflow files.
- CI README.
- Manual deploy skeleton.

Done criteria:
- Pull requests can be validated.
- Production deploy requires manual approval.
- Free/FOSS path is documented.
```

---

## Session 14 Prompt: Deployment scripts and release metadata

```text
Task: Add manual deployment pipeline scripts.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create scripts/deploy/preflight.sh.
2. Create scripts/deploy/deploy.sh.
3. Create scripts/deploy/healthcheck.sh.
4. Create scripts/deploy/verify-traffic.sh.
5. Create release metadata format under releases/README.md.
6. Deployment must capture current Git SHA, image digests, rendered Compose config, and timestamp before changes.
7. Deployment must require explicit confirmation or approved CI environment.
8. Create docs/runbooks/deploy.md.

Deliverables:
- Deploy scripts.
- Release metadata docs.
- Deployment runbook.

Done criteria:
- Deploy is not automatic.
- Preflight checks run before changes.
- Health and traffic verification run after changes.
```

---

## Session 15 Prompt: Rollback automation

```text
Task: Add rollback automation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create scripts/deploy/rollback.sh.
2. Rollback should restore previous Git SHA or release artifact, previous Compose config, previous image digests, previous config snapshot, and previous secrets references.
3. Include database restore hook but require explicit manual confirmation for destructive DB restores.
4. Integrate rollback call into deploy failure path as a documented option.
5. Create docs/runbooks/rollback.md.
6. Add tests or a dry-run mode.

Deliverables:
- rollback.sh.
- rollback runbook.
- dry-run/test mode.

Done criteria:
- Stateless service rollback is automatic-capable.
- Stateful rollback is conservative.
- Health verification runs after rollback.
```

---

## Session 16 Prompt: DNS filtering and split DNS

```text
Task: Add optional DNS filtering stack design.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/dns/compose.yml with profiles for AdGuard Home and Pi-hole, but document choosing one primary.
2. Add Unbound optional profile.
3. Create docs/architecture/dns.md explaining LAN DNS, Tailscale DNS, split DNS, upstreams, and failure handling.
4. Create docs/runbooks/dns.md.
5. Include Tailscale DNS integration notes.
6. Do not force DNS stack into production by default.

Deliverables:
- DNS stack with profiles.
- DNS architecture docs.
- DNS runbook.

Done criteria:
- AdGuard/Pi-hole choice is explicit.
- Split DNS is documented.
- DNS outage recovery is documented.
```

---

## Session 17 Prompt: First application template implementation

```text
Task: Add an example public and private application stack using the platform standards.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create stacks/apps/example-public-app/compose.yml with a harmless demo container such as whoami or nginx unprivileged.
2. Add Traefik labels for public route with placeholder domain.
3. Add security defaults and health check.
4. Create stacks/apps/example-private-app/compose.yml with no public exposure by default.
5. Create README.md for each app documenting networks, exposure, backup, health, rollback.
6. Add tests validating that only the public app attaches to proxy.

Deliverables:
- Example public app.
- Example private app.
- Service docs.
- Network exposure test.

Done criteria:
- Public exposure is explicit.
- Private app is not routed by Traefik.
- Templates teach future service pattern.
```

---

## Session 18 Prompt: Disaster recovery documentation

```text
Task: Create full disaster recovery documentation.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create docs/architecture/disaster-recovery.md.
2. Include recovery scenarios: bad deploy, broken Traefik, tunnel failure, host disk failure, lost age key, DB corruption, compromised service, hardware failure.
3. Define RTO/RPO by service class.
4. Include full host rebuild procedure.
5. Include emergency kit checklist.
6. Include quarterly restore drill procedure.

Deliverables:
- Disaster recovery doc.
- Restore drill checklist.

Done criteria:
- A new admin can rebuild on a laptop/NUC from backups.
- Emergency access via Tailscale/local console is documented.
```

---

## Session 19 Prompt: Multi-node scaling documentation

```text
Task: Add future expansion and multi-node scaling docs.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Create docs/architecture/scaling-roadmap.md.
2. Cover adding NAS, Raspberry Pi, NUC, mini PC, VPS.
3. Cover multiple Cloudflare tunnel connectors.
4. Cover multiple Tailscale subnet routers and exit nodes.
5. Cover multi-host Docker Compose, Ansible, Docker Swarm, Nomad, and Kubernetes/k3s migration paths.
6. Cover distributed storage options and warnings.
7. Create host inventory template.

Deliverables:
- Scaling roadmap.
- Host inventory template.

Done criteria:
- Future nodes can be added without redesign.
- Kubernetes/Nomad are migration paths, not day-one requirements.
```

---

## Session 20 Prompt: Final documentation review and consistency pass

```text
Task: Perform a final consistency review of the homelab-platform repository.

Session control / question gate:
- Ask clarifying questions first for any missing account, domain, token, key, credential, API, DNS, tunnel, Tailscale, Git/CI, SMTP/notification, backup, or proxy detail.
- Do not paste, hardcode, commit, or print real secrets; if needed, stop and request a secure local delivery method such as SOPS/age, environment variable, local secret file, or password manager.
- Ask whether HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, or reverse-proxy/domain settings are required.
- Verify each major step with commands, tests, file reads, config validation, or explicit inspection before continuing.
- Do not mark complete until every Done criterion is verified with evidence; do not move to the next session without explicit user green signal.

Requirements:
1. Check that all docs agree on network names.
2. Check that public ingress is always Cloudflare Tunnel -> Traefik.
3. Check that no docs recommend direct inbound router port forwards.
4. Check that secrets are always SOPS/age or placeholders.
5. Check that production deploy always requires manual approval.
6. Check that backup/restore/rollback docs are linked from README.md.
7. Check that every stack has a README.md.
8. Create docs/troubleshooting/common-failures.md if missing.
9. Produce a summary of inconsistencies fixed.

Deliverables:
- Consistency fixes.
- Common troubleshooting doc.
- Final review summary.

Done criteria:
- Documentation is coherent and self-documenting.
- Major runbooks are easy to find.
- Platform principles are consistently enforced.
```

---

# 28. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| PiKVM V4 resource limits | Monitoring/logging/CI may overload host | Keep retention low, avoid heavy CI on PiKVM, move heavy workloads to NUC later |
| Cloudflare dependency | Public ingress unavailable if Cloudflare/tunnel fails | Tailscale admin path, documented tunnel recovery, optional Tailscale Funnel emergency path |
| Tailscale account/control dependency | Private admin affected by account/control issues | Keep local console/OpenSSH fallback, evaluate Headscale later |
| Single-node failure | All services down | Encrypted backups, restore to laptop/NUC, future second node |
| Secret key loss | Cannot decrypt secrets | Offline age key backup, key custody runbook |
| Bad container update | Service outage | Pin versions, CI scan, manual deploy, rollback |
| Database migration failure | Data loss/outage | Pre-deploy DB dumps, backward-compatible migrations, manual DB rollback confirmation |
| Disk fills from logs/backups | Host instability | Docker log rotation, Loki retention, disk alerts, restic prune |
| Accidental public exposure | Security breach | Traefik `exposedByDefault=false`, network isolation, CI exposure tests |
| Raw Docker socket exposure | Host compromise | Avoid; use socket proxy if needed |
| Weak ACLs | Lateral movement | Tailscale ACL as code, regular review, tags |
| DNS outage | Clients lose resolution | Secondary resolver later, recovery runbook, avoid over-centralizing too soon |
| Backup silently broken | False sense of safety | Backup alerts, restic check, restore tests |
| Documentation drift | Recovery failure | Docs-as-code, review checklist, ADRs |
| Supply-chain vulnerabilities | Compromise/outage | Trivy/Grype scans, pinned images, SBOMs, update PRs |

---

# 29. Final Recommended Architecture

## 29.1 Final architecture summary

Start with:

- PiKVM V4 as a single production Docker Compose host.
- Cloudflare DNS + Cloudflare Tunnel for all public ingress.
- Traefik as the only internal reverse proxy and routing point.
- Tailscale as private admin plane with MagicDNS, ACLs, tags, and SSH.
- SOPS + age for GitOps-compatible secrets.
- Prometheus/Grafana/Alertmanager/Uptime Kuma for monitoring and alerting.
- Loki + Promtail/Alloy for centralized logs.
- restic for encrypted backups and restore tests.
- CI validation with GitHub Actions and a separately hosted local M3 Mac self-hosted runner initially; laptop deployment target only after explicit retarget approval.
- Manual approval required before production deployment.

## 29.2 Major decision justifications

| Decision | Justification |
|---|---|
| Docker Compose first | Stable, simple enough for one node, portable, easy to validate, no Kubernetes overhead |
| Traefik | Docker-native discovery, middleware, metrics, ACME, easy migration path |
| Cloudflare Tunnel | Required public access model, no inbound ports, hides home IP |
| Tailscale | Secure private admin, ACLs, MagicDNS, SSH, subnet/exit flexibility |
| SOPS + age | Lightweight FOSS secret workflow, GitOps-friendly, avoids heavy Vault day one |
| Authelia | Lightweight self-hosted auth and MFA for admin apps |
| Prometheus/Grafana | Standard OSS monitoring stack, portable to future platforms |
| Loki | Lightweight central logging integrated with Grafana |
| restic | Encrypted, deduplicated, backend-flexible backups with simple restore |
| Manual deploy approval | Prevents accidental production changes and aligns with production-grade operations |
| Multiple Docker networks | Enforces trust boundaries and limits lateral movement |
| CI validation before deploy | Finds YAML/Compose/secrets/security issues early |
| Rollback snapshots | Ensures failed deploys can recover quickly |

## 29.3 When to enable optional features

| Feature | Enable when |
|---|---|
| Tailscale subnet router | Remote access to LAN devices is needed |
| Tailscale exit node | You need trusted internet egress while traveling |
| Exit node + DNS filtering | Remote clients need consistent filtered DNS |
| AdGuard Home/Pi-hole | You want DNS filtering or split DNS beyond MagicDNS |
| Tailscale Serve | Temporary/private tailnet-only exposure is useful |
| Tailscale Funnel | Emergency/temporary public exposure; not default production path |
| CrowdSec | Once public apps receive real traffic |
| Forgejo/Woodpecker | When avoiding SaaS becomes more important than setup simplicity |
| Nomad/k3s | When multiple nodes and scheduling needs justify complexity |
| Distributed storage | Only after storage requirements exceed simple NAS/local volumes |

## 29.4 Final target diagram

```text
                                   +-----------------------+
                                   | GitOps Source of Truth|
                                   | repo + docs + secrets |
                                   +-----------+-----------+
                                               |
                                               v
                                   +-----------------------+
                                   | CI Validation          |
                                   | lint/test/scan/SBOM    |
                                   +-----------+-----------+
                                               | manual approval
                                               v
Internet --> Cloudflare DNS/Edge --> Cloudflare Tunnel --> Traefik
                                                                 |
          Tailscale private admin plane -------------------------+
                                                                 |
                              +----------------------------------+----------------------------------+
                              v                                  v                                  v
                       Public Apps                         Auth/Security                       Observability
                    proxy/public/db                     Authelia/CrowdSec                  Prom/Grafana/Loki
                              |                                  |                                  |
                              +----------------------------------+----------------------------------+
                                                                 v
                                                          Backups/restic
                                                                 |
                                                                 v
                                                        USB/NAS/SFTP/offline
```

---

# 30. Appendix: Operational Checklists

## 30.1 New service checklist

- [ ] Service has its own folder under `stacks/`.
- [ ] Service has README.
- [ ] Service uses pinned image version.
- [ ] Service runs non-root if possible.
- [ ] `no-new-privileges` enabled where compatible.
- [ ] Capabilities dropped where compatible.
- [ ] Read-only root filesystem where compatible.
- [ ] Health check defined.
- [ ] Restart policy defined.
- [ ] Only required Docker networks attached.
- [ ] No database attached to `proxy`.
- [ ] Traefik labels explicit if public.
- [ ] Auth middleware applied if sensitive.
- [ ] Secrets use SOPS.
- [ ] Volumes documented.
- [ ] Backup requirements documented.
- [ ] Monitoring/logging labels/config added.
- [ ] Rollback procedure documented.

## 30.2 Pre-deploy checklist

- [ ] Pull request reviewed.
- [ ] CI passed.
- [ ] Compose config validates.
- [ ] Secrets validation passed.
- [ ] Image scan reviewed.
- [ ] SBOM generated for custom images.
- [ ] Backup completed.
- [ ] Database dump completed if applicable.
- [ ] Rollback target known.
- [ ] Manual approval granted.

## 30.3 Post-deploy checklist

- [ ] Containers healthy.
- [ ] Traefik routers loaded.
- [ ] Public route works through Cloudflare.
- [ ] Private route works through Tailscale.
- [ ] Logs show no repeated errors.
- [ ] Metrics targets up.
- [ ] Uptime Kuma checks passing.
- [ ] Backup schedule still active.
- [ ] Release marked successful.
- [ ] Admin notified.

## 30.4 Monthly maintenance checklist

- [ ] Review disk usage.
- [ ] Review failed login/security logs.
- [ ] Review image update PRs.
- [ ] Review backup success.
- [ ] Perform sample restore.
- [ ] Check certificate expiry.
- [ ] Review Tailscale devices and ACLs.
- [ ] Review public routes.
- [ ] Update documentation if drift found.

## 30.5 Quarterly disaster recovery checklist

- [ ] Restore latest backup to temporary location.
- [ ] Validate Compose config from restored files.
- [ ] Restore one database dump to temporary DB.
- [ ] Start one non-critical restored service.
- [ ] Confirm age key backup is accessible.
- [ ] Confirm restic password backup is accessible.
- [ ] Review host rebuild runbook.
- [ ] Review emergency contacts/accounts.
- [ ] Record test result and fixes.

---

# 31. M3 Mac Local Development and LLM Flow Checklist

This implementation starts on an M3 Mac for speed and local iteration. The laptop deployment target is introduced only after the user is satisfied with local Mac validation and explicitly approves CI/CD retargeting.

The most important operating rule is: **do not mark checklist items complete until they are actually done and verified.** During work, checklist boxes remain unchecked. At the end of a session, only verified items may be marked complete, and each checked item must include evidence.

## 31.1 M3 Mac-first workflow

```text
M3 Mac local workstation
   |
   | edit, lint, validate, render Compose, smoke-test locally
   v
GitHub repository
   |
   | GitHub Actions validation using local M3 Mac self-hosted runner
   v
Release candidate artifacts
   |
   | only after explicit user approval
   v
Retarget CI/CD to laptop
   |
   | manual approval, dry-run, health checks, rollback checks
   v
Laptop deployment target
```

## 31.2 Required LLM flow checklist

The LLM should copy this checklist into each implementation session. It must keep boxes unchecked until final verification.

```markdown
## Session checklist - keep unchecked until final verification

- [ ] Question gate completed or explicitly deferred as not needed for this phase.
- [ ] Account, token, domain, DNS, Tailscale, GitHub, notification, backup, and proxy needs identified without exposing secrets.
- [ ] Proxy requirements checked: HTTP_PROXY, HTTPS_PROXY, NO_PROXY, corporate/LAN proxy, and reverse-proxy/domain settings.
- [ ] M3 Mac local-development impact checked, including Apple Silicon/ARM64 compatibility.
- [ ] Files to change identified.
- [ ] Existing files read before editing.
- [ ] Minimal changes implemented.
- [ ] No plaintext secrets created.
- [ ] Local validation run on the M3 Mac or documented as not applicable.
- [ ] CI validation path identified.
- [ ] Config syntax validated where applicable.
- [ ] Tests or smoke checks run where applicable.
- [ ] Evidence artifacts/logs identified.
- [ ] Done criteria verified with evidence.
- [ ] Final summary includes checked items only after verification.
- [ ] Next session not started; waiting for explicit user green signal.
```

## 31.3 LLM stop conditions

Stop and ask the user before continuing if:

- A real secret, token, password, API key, private key, tunnel credential, or GitHub runner token is required.
- A domain, DNS zone, Tailscale tailnet, GitHub repo, or account ID is required and unknown.
- A command could be destructive on the M3 Mac or future laptop.
- A proxy may be required but proxy settings are unknown.
- A step would expose any service publicly.
- A step would retarget CI/CD to the laptop without explicit approval.
- A validation step fails.
- The next prompt/session would start without the user's green signal.

## 31.4 Final evidence table template

At the end of every session, include an evidence table. A row can be checked only if there is real evidence.

```markdown
## Final verification evidence

| Item | Status | Evidence |
|---|---|---|
| Question gate completed | [ ] / [x] | Questions asked, answers received, or reason not needed |
| Proxy requirements checked | [ ] / [x] | User answer, placeholder config, or documented deferral |
| Files changed | [ ] / [x] | File paths |
| Existing files read first | [ ] / [x] | File paths read |
| Secrets protected | [ ] / [x] | No plaintext secrets; placeholders/SOPS only |
| Local Mac validation | [ ] / [x] | Command and result, or documented not applicable |
| CI validation path | [ ] / [x] | Workflow/job name or documented future step |
| Config validation | [ ] / [x] | Command and result |
| Tests/smoke checks | [ ] / [x] | Command and result |
| Done criteria met | [ ] / [x] | Evidence summary |
| Waiting for green signal | [ ] / [x] | Explicit statement that next session is not started |
```

---

# 32. Detailed GitHub Actions CI/CD Design

This is the detailed CI/CD plan for stability and ease of development. The current choice is **GitHub Actions with a separately hosted local M3 Mac self-hosted runner**. The runner validates the repository quickly and safely. The laptop is not a deployment target until the user explicitly approves the retargeting gate.

## 32.1 CI/CD non-negotiable rules

| Rule | Requirement |
|---|---|
| Every change is validated | No step is complete without local or CI evidence. |
| Every PR has checks | PRs must pass required GitHub checks before merge. |
| Every failure stops progress | Do not move to the next prompt/session while CI is red. |
| Every skipped test is explained | Skips require a reason and follow-up if still needed. |
| Every deployment is manual | Nothing deploys to production automatically. |
| Every release has artifacts | Rendered configs, reports, SBOMs, and rollback metadata are preserved. |
| Secrets are protected | No plaintext secrets in repo, logs, artifacts, or workflow output. |
| Laptop deploy is disabled now | Laptop deployment is introduced only after explicit user approval. |

## 32.2 CI/CD architecture

```text
Developer on M3 Mac
   |
   | local scripts: make validate, make test, make evidence
   v
GitHub repo
   |
   | push / pull request
   v
GitHub Actions control plane
   |
   +-- CI contract checks
   +-- lint checks
   +-- Compose rendering
   +-- secret leak checks
   +-- security scans
   +-- M3 Mac Docker integration tests
   +-- release candidate artifact generation
   |
   +-- laptop deployment workflow
          disabled until explicit approval
```

## 32.3 Runner strategy

### Current runner: M3 Mac self-hosted validation runner

| Item | Value |
|---|---|
| Runner type | GitHub Actions self-hosted runner |
| Host | Local M3 Mac, hosted separately from production |
| Purpose | Fast validation, linting, Compose rendering, integration tests, release artifacts |
| Suggested labels | `self-hosted`, `macOS`, `ARM64`, `m3`, `homelab-validation` |
| Docker runtime | Docker Desktop, OrbStack, Colima, or user-approved runtime |
| Trust level | Trusted validation machine, not production target |
| Production secrets | Avoid initially |
| Public exposure | None |

### Future target: laptop

| Item | Rule |
|---|---|
| Activation | Only after explicit user approval |
| Role | Deployment target or deployment runner |
| Access | Tailscale SSH, local runner, or remote Docker context |
| Required proof | Dry-run deploy, health check, rollback dry-run, secret strategy, proxy check |

## 32.4 M3 Mac runner hardening checklist

- Use a dedicated macOS user for the runner if practical.
- Do not run the runner as an administrator unless specifically required.
- Do not store production secrets in the runner workspace.
- Do not allow untrusted fork pull requests to execute on the self-hosted runner.
- Use branch protection and required checks.
- Use GitHub Environments for manual approval gates.
- Use least-privilege `permissions:` in every workflow.
- Use `timeout-minutes:` in every job.
- Use `concurrency:` to prevent overlapping jobs.
- Use cleanup steps with `if: always()` for Docker integration tests.
- Upload failure logs as artifacts.
- Keep runner software and Docker runtime updated on a controlled schedule.
- Keep laptop deployment credentials away from the Mac runner until the retarget phase.

## 32.5 Repository branch protection

Protect `main` with:

- Pull request required before merge.
- Required status checks before merge.
- Branch must be up to date before merge.
- Conversation resolution required.
- Force pushes blocked.
- Branch deletion blocked.
- Reviews required when practical.

Required checks should be stable and human-readable:

```text
ci-local-contract
lint-yaml-markdown-shell
validate-compose
validate-secrets
scan-config
mac-compose-integration
ci-evidence-summary
```

## 32.6 GitHub Environments

| Environment | Purpose | Approval |
|---|---|---|
| `local-mac-validation` | M3 Mac validation jobs | No production approval |
| `release-candidate` | Generate release artifacts | Optional manual approval |
| `laptop-staging` | Future laptop dry-run/staging | Manual approval required |
| `laptop-production` | Future laptop production | Manual approval required |

The `laptop-production` environment should not be used until the laptop retarget checklist is complete.

## 32.7 Secrets strategy

Initial rule: **do not put production secrets into GitHub Actions unless a phase explicitly needs them and a protected environment exists.**

| Phase | Secret handling |
|---|---|
| Local Mac development | Placeholders or local SOPS/age only |
| Pull request validation | No production secrets |
| M3 Mac integration tests | Local test placeholders only |
| Release candidate | No production secrets unless signing is added later |
| Laptop staging | Protected environment secrets or SOPS on target |
| Laptop production | Prefer SOPS on laptop target; GitHub Environment secrets only if justified |

Secret rules:

- Never echo secrets.
- Never upload decrypted secrets as artifacts.
- Never run production-secret jobs on untrusted PRs.
- Use scoped Cloudflare tokens, never global keys.
- Use short-lived Tailscale auth keys only when required.
- Prefer target-side SOPS decryption over sending secrets through CI.

## 32.8 Proxy support

The CI design must support networks that require proxy settings.

Ask and document whether these are needed:

- `HTTP_PROXY`
- `HTTPS_PROXY`
- `NO_PROXY`
- Docker daemon proxy
- Docker build proxy args
- Git proxy
- Homebrew proxy on macOS
- npm/pnpm/yarn proxy
- pip/Poetry proxy
- GitHub runner service proxy

Recommended `NO_PROXY` baseline:

```text
localhost,127.0.0.1,::1,.local,.test,.internal,home.arpa,lab.internal,100.64.0.0/10,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

Do not hardcode proxy credentials. Use local runner environment variables or GitHub Environment secrets only when required.

## 32.9 Local and CI parity

Every CI check should have a local command so failures are easy to reproduce on the M3 Mac.

Recommended developer commands:

```bash
make validate
make lint
make compose-config
make secrets-check
make security-scan
make integration-test
make evidence
```

Recommended script layout:

```text
scripts/ci/ci-contract.sh
scripts/ci/ci-lint.sh
scripts/ci/ci-scan.sh
scripts/ci/generate-evidence.sh
scripts/validate/validate-all.sh
scripts/validate/validate-yaml.sh
scripts/validate/validate-markdown.sh
scripts/validate/validate-shell.sh
scripts/validate/validate-compose.sh
scripts/validate/validate-secrets.sh
scripts/validate/validate-traefik.sh
scripts/validate/validate-cloudflared.sh
scripts/validate/validate-networks.sh
scripts/validate/validate-permissions.sh
scripts/test/integration-compose.sh
scripts/test/smoke-local.sh
scripts/test/cleanup-compose.sh
```

## 32.10 Workflow layout

Recommended GitHub Actions workflow files:

```text
.github/workflows/
  00-ci-contract.yml
  01-lint.yml
  02-validate-compose.yml
  03-secrets.yml
  04-security-scan.yml
  05-mac-integration.yml
  06-release-candidate.yml
  07-deploy-laptop-disabled-until-approved.yml
```

## 32.11 Workflow details

### `00-ci-contract.yml`

Purpose:

- Prove required directories and scripts exist.
- Prove the laptop deployment workflow is disabled until approval.
- Prove no plaintext production env files exist.
- Publish a CI evidence summary.

Required checks:

- `README.md` exists.
- `docs/`, `scripts/`, `compose/`, `stacks/`, `secrets/`, and `.github/workflows/` exist when applicable.
- No `.env.production` committed.
- No deployment workflow can run without manual approval.

### `01-lint.yml`

Purpose:

- YAML, Markdown, shell, Dockerfile, and EditorConfig checks.

Tools:

- `yamllint`
- `markdownlint-cli` or `markdownlint-cli2`
- `shellcheck`
- `shfmt`
- `hadolint`
- `editorconfig-checker`

### `02-validate-compose.yml`

Purpose:

- Render Compose configs and detect unsafe runtime configuration.

Required checks:

- `docker compose config` succeeds.
- No accidental public `ports:` mappings unless documented.
- Databases are not attached to `proxy`.
- Critical services have restart policies.
- Critical services have health checks.
- Images are version-pinned.
- Required networks and volumes are declared.

### `03-secrets.yml`

Purpose:

- Prevent secret leaks and enforce SOPS/placeholder patterns.

Required checks:

- `gitleaks` passes.
- No decrypted SOPS files are committed.
- No real `.env` files are committed.
- `.env.example` files contain placeholders only.
- SOPS files follow naming conventions.

### `04-security-scan.yml`

Purpose:

- Scan filesystem, configuration, and images where available.

Tools:

- Trivy filesystem/config scan.
- Syft SBOM generation.
- Grype optional vulnerability scan.
- SARIF upload optional.

### `05-mac-integration.yml`

Purpose:

- Run Docker Compose integration checks on the M3 Mac runner.

Required checks:

- Docker runtime available.
- Compose available.
- ARM64 image compatibility checked.
- Test stack starts.
- Health endpoints pass.
- Network isolation checks pass.
- Logs captured on failure.
- Cleanup always runs.

### `06-release-candidate.yml`

Purpose:

- Generate release evidence without deployment.

Artifacts:

- Git SHA.
- changed files.
- rendered Compose config.
- validation reports.
- image list/digests where available.
- SBOM.
- rollback metadata.
- release notes.

### `07-deploy-laptop-disabled-until-approved.yml`

Purpose:

- Placeholder for future laptop deployment.
- Must remain guarded until explicit approval.

Required guards:

- `workflow_dispatch` only.
- Protected `laptop-production` environment.
- Required reviewer approval.
- Explicit typed input such as `I_APPROVE_LAPTOP_DEPLOY`.
- Presence of `docs/approvals/laptop-cicd-retarget-approved.md`.
- Dry-run first.

## 32.12 Reference workflow skeletons

### Lint workflow skeleton

```yaml
name: 01 Lint

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: lint-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: lint-yaml-markdown-shell
    runs-on: [self-hosted, macOS, ARM64, m3, homelab-validation]
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Show runner context
        run: |
          uname -a
          git --version
      - name: Run lint script
        run: ./scripts/ci/ci-lint.sh
```

### Compose validation skeleton

```yaml
name: 02 Validate Compose

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: compose-${{ github.ref }}
  cancel-in-progress: true

jobs:
  compose:
    name: validate-compose
    runs-on: [self-hosted, macOS, ARM64, m3, homelab-validation]
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - name: Verify Docker
        run: |
          docker version
          docker compose version
      - name: Render Compose configs
        run: ./scripts/validate/validate-compose.sh
      - name: Upload rendered Compose evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: compose-rendered-${{ github.run_id }}
          path: artifacts/compose/
          if-no-files-found: warn
          retention-days: 14
```

### M3 Mac integration skeleton

```yaml
name: 05 M3 Mac Integration

on:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: mac-integration-${{ github.ref }}
  cancel-in-progress: true

jobs:
  integration:
    name: mac-compose-integration
    runs-on: [self-hosted, macOS, ARM64, m3, homelab-validation]
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Show platform
        run: |
          uname -m
          docker version
          docker compose version
      - name: Run integration tests
        run: ./scripts/test/integration-compose.sh
      - name: Capture Docker diagnostics
        if: always()
        run: |
          mkdir -p artifacts/docker
          docker ps -a > artifacts/docker/containers.txt || true
          docker images > artifacts/docker/images.txt || true
          docker network ls > artifacts/docker/networks.txt || true
      - name: Cleanup test stack
        if: always()
        run: ./scripts/test/cleanup-compose.sh
      - name: Upload integration evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: mac-integration-${{ github.run_id }}
          path: artifacts/
          if-no-files-found: warn
          retention-days: 14
```

### Laptop deployment guard skeleton

```yaml
name: 07 Deploy Laptop - Disabled Until Approved

on:
  workflow_dispatch:
    inputs:
      confirm_laptop_deploy:
        description: Type I_APPROVE_LAPTOP_DEPLOY to continue
        required: true
        type: string
      dry_run:
        description: Run deployment in dry-run mode
        required: true
        default: true
        type: boolean

permissions:
  contents: read

concurrency:
  group: laptop-deploy
  cancel-in-progress: false

jobs:
  guard:
    name: laptop-deploy-approval-guard
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - name: Enforce explicit approval
        run: |
          test "${{ inputs.confirm_laptop_deploy }}" = "I_APPROVE_LAPTOP_DEPLOY"
          test -f docs/approvals/laptop-cicd-retarget-approved.md
```

## 32.13 Evidence artifacts

Every important workflow should publish evidence that the user can inspect.

| Artifact | Produced by | Purpose |
|---|---|---|
| `lint-report-*` | lint | Lint results |
| `compose-rendered-*` | Compose validation | Exact rendered Compose config |
| `secrets-validation-*` | secret checks | Secret leak and placeholder validation |
| `security-scan-*` | security scan | Trivy/Grype reports |
| `sbom-*` | security/release | SBOM for custom images/filesystem |
| `mac-integration-*` | M3 integration | Docker status, logs, network info |
| `release-candidate-*` | release | Git SHA, image digests, config, rollback metadata |
| `deploy-dry-run-*` | future deploy | Laptop preflight and dry-run result |

Artifacts must never contain decrypted secrets.

## 32.14 User checking workflow

For every PR or CI run, the user should check:

1. All required GitHub checks are green.
2. The CI evidence summary exists.
3. Rendered Compose artifact exists if Compose files changed.
4. Secret validation artifact exists if secrets/config changed.
5. M3 Mac integration artifact exists if runtime behavior changed.
6. No laptop deployment workflow ran automatically.
7. No real secrets appear in logs.
8. Any skipped test has a documented reason.
9. Any warning has a follow-up task.

## 32.15 Validation contract for every step

Before implementing a step, define the validation contract:

```markdown
## Validation contract for this step

- Change being made:
- Files expected to change:
- Local validation command:
- CI validation job:
- Smoke test:
- Rollback or cleanup command:
- Evidence artifact expected:
- Done criteria:
```

No step is complete until its validation contract is satisfied.

## 32.16 Required validation by change type

| Change type | Required local validation | Required CI validation |
|---|---|---|
| Markdown docs | markdown lint, link sanity | lint |
| YAML config | YAML parse/lint | lint + config validation |
| Compose file | `docker compose config` | validate-compose + security checks |
| Traefik config | render config, start test stack | validate-compose + mac integration |
| Cloudflare tunnel config | YAML parse, ingress sanity | cloudflared validation |
| Secret template | secret scan, placeholder check | validate-secrets |
| Shell script | shellcheck, shfmt, dry-run | lint + script test |
| Dockerfile | hadolint, build | security scan + integration |
| Monitoring config | promtool if available | monitoring validation |
| Backup script | shellcheck, dry-run | backup validation |
| Deploy script | shellcheck, dry-run | deploy dry-run only |
| Rollback script | shellcheck, dry-run | rollback dry-run only |

## 32.17 Stability controls

- Use `timeout-minutes` on every job.
- Use `concurrency` groups.
- Use `cancel-in-progress: true` for validation.
- Use `cancel-in-progress: false` for deploy.
- Use cleanup steps with `if: always()`.
- Upload logs on failure.
- Keep artifact retention short for PRs and longer for releases.
- Pin tools or install deterministic versions.
- Avoid `latest` tags unless intentionally testing update behavior.
- Separate required checks from optional checks.
- Document every skipped check.

## 32.18 Ease-of-development controls

- Local `make validate` should run the same scripts as CI.
- CI errors should show the local command to reproduce.
- Heavy integration tests should run only when relevant files change.
- Job names should be stable.
- Artifacts should be named consistently.
- Mac-specific behavior should be documented.
- ARM64 compatibility issues should explain the fix.
- CI should fail fast for syntax errors and collect diagnostics for runtime failures.

## 32.19 Path filters for speed

| Paths changed | Workflows |
|---|---|
| `docs/**`, `README.md` | docs lint |
| `compose/**`, `stacks/**` | lint, Compose validation, security, integration |
| `scripts/**` | shell lint, script tests |
| `secrets/**`, `.sops.yaml` | secret validation |
| `.github/workflows/**`, `ci/**` | all CI contract checks |
| `infra/tailscale/**` | policy validation if available |
| `infra/cloudflare/**` | tunnel/DNS config validation |

Path filters must not skip security checks for files that affect deployment.

## 32.20 Laptop retargeting checklist

Do not retarget CI/CD to the laptop until all of this is true:

- M3 Mac local validation is stable.
- User explicitly says the Mac-local result is satisfactory.
- Laptop OS and architecture are documented.
- Laptop Docker runtime is documented.
- Laptop Tailscale connectivity is tested if used.
- Laptop deploy user is least-privilege.
- Laptop secret strategy is documented.
- Laptop proxy requirements are documented.
- Dry-run deploy passes.
- Rollback dry-run passes.
- `laptop-production` GitHub Environment has manual approval.
- Deployment workflow requires explicit typed confirmation.

## 32.21 CI/CD failure response

When CI fails:

1. Stop; do not move to the next prompt.
2. Read the failing job log.
3. Classify the failure: code, config, tool, runner, network, proxy, architecture, or flaky dependency.
4. Fix root cause.
5. Rerun the smallest relevant local command.
6. Rerun CI.
7. Update docs/runbooks if the failure teaches an operational lesson.
8. Include failure and fix evidence in the final summary.

## 32.22 CI/CD definition of done

CI/CD work is not done until:

- Workflows exist or are documented for the current phase.
- Local Mac validation commands exist.
- CI uses the same scripts as local validation.
- Required checks are documented.
- Secrets are protected.
- Proxy support is considered.
- Artifacts are generated.
- User can inspect clear GitHub checks.
- Laptop deploy remains disabled until approved.
- Final summary includes exact evidence.

---

# 33. Daily Backup and One-Shot Git Checkpoint Restore

The backup and restore experience should feel simple and intuitive:

```bash
make checkpoint
make backup
make restore CHECKPOINT=checkpoint-2026-08-04-prod DRY_RUN=1
make restore CHECKPOINT=checkpoint-2026-08-04-prod CONFIRM_RESTORE=checkpoint-2026-08-04-prod
```

The operator should not need to remember which Docker volumes, database dumps, config files, certificate files, image versions, or secrets belong together. A **Git checkpoint** ties them together in one manifest.

## 33.1 Core idea

Git stores platform code and manifests. Restic stores data. The checkpoint manifest links them.

```text
Git checkpoint tag / commit
   |
   +-- Compose files
   +-- Traefik/cloudflared configs
   +-- SOPS-encrypted secrets
   +-- restore manifest YAML
   |      +-- restic snapshot IDs
   |      +-- Docker volume map
   |      +-- database dump references
   |      +-- image tags/digests
   |      +-- host/runtime metadata
   |      +-- validation evidence
   |
   v
Restic encrypted repository
   +-- Docker volume snapshots
   +-- bind-mount data snapshots
   +-- database dumps
   +-- ACME/certificates
   +-- selected logs
```

Git should not contain raw Docker volume data, decrypted secrets, database dumps, or certificates. Git contains the checkpoint manifest and encrypted config/secrets only. Restic contains the encrypted data snapshots.

## 33.2 What a checkpoint means

A checkpoint is a named, restorable platform state.

Example checkpoint ID:

```text
checkpoint-2026-08-04-0200-prod
```

It should identify:

- Git commit SHA.
- Optional Git tag.
- Environment name, such as `local`, `staging`, `prod`, or `laptop-prod`.
- Hostname and architecture.
- Rendered Compose config hash.
- Image tags and digests.
- Restic repository ID.
- Restic snapshot IDs.
- Docker volume map.
- Database dump files and checksums.
- SOPS-encrypted secret file versions.
- Certificate/ACME backup reference.
- Validation and health-check status.

## 33.3 Recommended checkpoint files

```text
releases/
  checkpoints/
    checkpoint-2026-08-04-0200-prod.yaml
    checkpoint-2026-08-04-0200-prod.sha256
    latest-prod.txt

scripts/
  backup/
    checkpoint.sh
    backup.sh
    backup-volumes.sh
    backup-databases.sh
    backup-configs.sh
    verify-backup.sh
    list-checkpoints.sh
    restore-checkpoint.sh
    restore-volume.sh
    restore-database.sh
    restore-test.sh

docs/
  runbooks/
    one-shot-restore.md
    daily-backup.md
```

## 33.4 Checkpoint manifest example

This is a conceptual manifest. It should be generated automatically by `scripts/backup/checkpoint.sh`.

```yaml
apiVersion: homelab/v1
kind: RestoreCheckpoint
metadata:
  id: checkpoint-2026-08-04-0200-prod
  createdAt: "2026-08-04T02:00:00-04:00"
  environment: prod
  host: laptop-prod-01
  architecture: arm64
  createdBy: systemd-timer

git:
  repository: git@github.com:example/homelab-platform.git
  branch: main
  commit: abcdef1234567890abcdef1234567890abcdef12
  tag: checkpoint-2026-08-04-0200-prod
  dirtyTreeAllowed: false

compose:
  projectName: homelab
  files:
    - compose/production.yml
    - compose/networks.yml
  renderedConfig: releases/rendered/production-checkpoint-2026-08-04-0200-prod.yml
  renderedConfigSha256: PLACEHOLDER_SHA256

images:
  - service: traefik
    image: traefik:v3.1.0
    digest: sha256:PLACEHOLDER
  - service: cloudflared
    image: cloudflare/cloudflared:2026.8.0
    digest: sha256:PLACEHOLDER

secrets:
  backend: sops-age
  encryptedFiles:
    - secrets/production/cloudflare.sops.yaml
    - secrets/production/traefik.sops.yaml
    - secrets/production/restic.sops.yaml
  ageRecipientFingerprint: PLACEHOLDER_PUBLIC_FINGERPRINT

restic:
  repositoryName: homelab-prod
  repositoryId: PLACEHOLDER_RESTIC_REPOSITORY_ID
  snapshots:
    configs: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    dockerVolumes: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    databases: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    certificates: PLACEHOLDER_RESTIC_SNAPSHOT_ID
    logs: PLACEHOLDER_RESTIC_SNAPSHOT_ID

volumes:
  namedVolumes:
    - name: grafana-data
      service: grafana
      restorePath: /var/lib/docker/volumes/grafana-data/_data
      snapshotGroup: dockerVolumes
    - name: prometheus-data
      service: prometheus
      restorePath: /var/lib/docker/volumes/prometheus-data/_data
      snapshotGroup: dockerVolumes
  bindMounts:
    - service: traefik
      hostPath: /srv/homelab/stacks/proxy/traefik
      snapshotGroup: configs

databases:
  dumps:
    - service: postgres-example
      engine: postgres
      dumpPath: backups/databases/postgres-example.sql.gz
      sha256: PLACEHOLDER_SHA256
      snapshotGroup: databases

certificates:
  acmeFile: stacks/proxy/traefik/acme/acme.json
  snapshotGroup: certificates

validation:
  backupCompleted: true
  resticCheckCompleted: true
  composeConfigValidated: true
  healthChecksPassedBeforeBackup: true
  restoreTestRequired: true
  restoreTestStatus: pending
```

## 33.5 Daily backup schedule

Recommended daily flow:

```text
02:00 daily
   |
   v
Preflight
   +-- confirm disk space
   +-- confirm restic repository reachable
   +-- confirm Git tree clean or explicitly allow dirty=false
   +-- confirm Docker reachable
   +-- confirm SOPS encrypted files present
   |
   v
Create database dumps
   +-- pg_dump / mysqldump / sqlite safe copy
   |
   v
Backup configs, encrypted secrets, volumes, DB dumps, certs, selected logs
   |
   v
Run restic forget/prune policy
   |
   v
Run restic check or lightweight verify
   |
   v
Generate checkpoint manifest
   |
   v
Commit manifest and optionally create Git tag
   |
   v
Push Git checkpoint metadata
   |
   v
Send notification and update monitoring
```

Recommended schedule:

| Time | Task |
|---|---|
| Daily 02:00 | Full logical backup + volume backup + checkpoint manifest |
| Daily 02:30 | Lightweight restic check / snapshot verify |
| Weekly Sunday 03:00 | Full restic repository check |
| Weekly Sunday 04:00 | Restore-test one non-critical service to temporary path |
| Monthly | Full one-shot restore drill to temporary host/path |

## 33.6 What gets backed up daily

| Data | Backup location | Notes |
|---|---|---|
| Git repository | Git remote + restic config backup | Git remote alone is not enough. |
| Compose files | Git + restic | Rendered Compose config stored as artifact/checkpoint. |
| Traefik/cloudflared configs | Git + restic | Secrets excluded or encrypted only. |
| SOPS-encrypted secrets | Git + restic | Safe to store encrypted copies. |
| Decrypted runtime secrets | Avoid; restic only if unavoidable | Prefer regenerate from SOPS. |
| Docker named volumes | restic | Use volume map in checkpoint. |
| Bind-mount data | restic | Prefer `/srv/homelab/data/<service>` for simplicity. |
| Databases | logical dump + restic | Dump before volume backup. |
| ACME/certificates | restic | Restore permissions must be strict. |
| Logs | Loki retention + selected restic | Do not over-backup noisy logs. |
| Release metadata | Git + restic | Needed for rollback and audit. |

## 33.7 Prefer intuitive bind-mount layout

For easy restore, prefer a consistent data layout instead of anonymous or hard-to-find mounts.

Recommended host layout:

```text
/srv/homelab/
  repo/                         # Git checkout
  data/
    grafana/
    prometheus/
    loki/
    authelia/
    traefik/
    postgres-example/
  backups/
    database-dumps/
    restore-tests/
  runtime/
    env/                        # generated env files, permissions 0600
    rendered-compose/
  logs/
```

Named Docker volumes are still acceptable, but every named volume must appear in the checkpoint manifest. Anonymous volumes should be avoided for production services.

## 33.8 Simple Makefile interface

The operator should have a small set of obvious commands.

```makefile
.PHONY: checkpoint backup restore restore-dry-run list-checkpoints verify-backup restore-test

checkpoint:
	./scripts/backup/checkpoint.sh

backup:
	./scripts/backup/backup.sh

list-checkpoints:
	./scripts/backup/list-checkpoints.sh

restore-dry-run:
	./scripts/backup/restore-checkpoint.sh --checkpoint $(CHECKPOINT) --dry-run

restore:
	./scripts/backup/restore-checkpoint.sh --checkpoint $(CHECKPOINT)

verify-backup:
	./scripts/backup/verify-backup.sh

restore-test:
	./scripts/backup/restore-test.sh
```

Expected usage:

```bash
make list-checkpoints
make restore-dry-run CHECKPOINT=checkpoint-2026-08-04-0200-prod
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod
```

## 33.9 One-shot restore workflow

The restore command should be safe by default.

```text
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod DRY_RUN=1
   |
   v
Load checkpoint manifest
   |
   v
Verify Git commit/tag exists
   |
   v
Verify restic repository reachable
   |
   v
Verify all snapshot IDs exist
   |
   v
Verify SOPS encrypted secrets exist
   |
   v
Render restore plan
   |
   v
Stop unless explicit confirmation is supplied
```

Real restore:

```text
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod CONFIRM_RESTORE=checkpoint-2026-08-04-0200-prod
   |
   v
Preflight and confirmation
   |
   v
Stop current stack safely
   |
   v
Checkout Git checkpoint commit/tag
   |
   v
Decrypt/generate runtime secrets locally
   |
   v
Restore configs and certificates
   |
   v
Restore Docker volumes and bind mounts
   |
   v
Restore database dumps if applicable
   |
   v
Pull pinned images
   |
   v
Render Compose config
   |
   v
Start core services
   |
   v
Start dependent services
   |
   v
Run health checks
   |
   v
Run traffic checks
   |
   v
Mark restore successful or stop for manual recovery
```

## 33.10 Restore safety gates

The restore script must refuse to proceed unless:

- `CHECKPOINT` is provided.
- Checkpoint manifest exists.
- Checkpoint manifest checksum matches.
- Git commit/tag exists.
- Restic repository is reachable.
- Referenced restic snapshots exist.
- Target restore path is known.
- Current state is snapshotted before destructive restore.
- User passes explicit confirmation for real restore.
- For database overwrite, user passes an additional database confirmation.

Example confirmation pattern:

```bash
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod CONFIRM_RESTORE=checkpoint-2026-08-04-0200-prod
```

For destructive database restore:

```bash
make restore CHECKPOINT=checkpoint-2026-08-04-0200-prod CONFIRM_RESTORE=checkpoint-2026-08-04-0200-prod CONFIRM_DATABASE_RESTORE=I_UNDERSTAND_DATABASE_OVERWRITE
```

## 33.11 Restore modes

| Mode | Command | Purpose |
|---|---|---|
| Dry run | `make restore-dry-run CHECKPOINT=...` | Show what would be restored. |
| Config only | `make restore-config CHECKPOINT=...` | Restore Git/config/secrets templates only. |
| One service | `make restore-service CHECKPOINT=... SERVICE=grafana` | Restore one service volume/config. |
| Full stack | `make restore CHECKPOINT=...` | Restore complete platform state. |
| Test restore | `make restore-test CHECKPOINT=...` | Restore to temp path/project. |

## 33.12 Database handling

Database volumes alone are not enough for reliable backups. Use logical dumps.

| Database | Backup method | Restore method |
|---|---|---|
| Postgres | `pg_dump` or `pg_dumpall` | restore into fresh container/db |
| MariaDB/MySQL | `mysqldump` or `mariadb-dump` | restore into fresh container/db |
| SQLite | app-aware stop/lock and file copy | restore DB file with ownership fix |
| Redis | RDB/AOF copy after save | restore file and restart |

The checkpoint manifest should record database dump path, engine, compression, checksum, and restic snapshot group.

## 33.13 Volume handling

Docker volume restore must be predictable.

Rules:

- Avoid anonymous volumes.
- Prefer named volumes or clear bind mounts.
- Every persistent volume appears in the checkpoint manifest.
- Volumes are restored before dependent services start.
- Ownership and permissions are validated after restore.
- Databases restore from logical dumps unless explicitly using volume-level restore for a known-safe engine.

## 33.14 Daily backup verification

A daily backup is not successful just because the command exited. It must verify:

- Restic snapshot created.
- Database dumps created and checksummed.
- Checkpoint manifest generated.
- Manifest checksum generated.
- Git checkpoint metadata committed or stored.
- Optional Git tag created.
- `restic snapshots` sees the new snapshots.
- `restic check` or lightweight verify passes according to schedule.
- Uptime Kuma/ntfy/Gotify notification sent.

## 33.15 Restore test verification

Weekly restore test should:

1. Create a temporary restore directory.
2. Restore selected config files.
3. Restore one small volume or service dataset.
4. Restore one database dump to a temporary container if available.
5. Run `docker compose config` against restored config.
6. Start a non-conflicting test Compose project if safe.
7. Run health/smoke checks.
8. Delete temporary resources.
9. Record result in `docs/runbooks/restore-tests.md` or `releases/checkpoints/restore-test-log.md`.

## 33.16 Git checkpoint retention

Recommended retention:

| Checkpoint type | Retention |
|---|---|
| Daily checkpoint manifests | 30-60 days in Git, or longer if small |
| Weekly checkpoint tags | 12 weeks |
| Monthly checkpoint tags | 12-24 months |
| Pre-deploy checkpoints | Keep at least last 20 deploys |
| Major upgrade checkpoints | Keep indefinitely or until superseded |

Restic retention can be longer than Git manifest retention, but do not delete manifests needed to understand restic snapshots that still exist.

## 33.17 CI/CD integration

GitHub Actions should validate backup and restore scripts without touching production data.

Required CI checks:

- Shellcheck backup scripts.
- Validate checkpoint manifest schema.
- Validate Makefile targets exist.
- Run restore dry-run against a fixture checkpoint.
- Ensure restore defaults to dry-run/safe behavior.
- Ensure destructive restore requires explicit confirmation.
- Ensure artifacts do not contain secrets.

Suggested fixture:

```text
tests/fixtures/checkpoints/checkpoint-fixture.yaml
tests/fixtures/restic-snapshots/sample-snapshots.txt
```

## 33.18 One-shot restore definition of done

The one-shot restore system is not done until:

- `make checkpoint` creates a manifest.
- `make backup` creates restic snapshots.
- `make list-checkpoints` shows available checkpoints.
- `make restore-dry-run CHECKPOINT=...` prints a safe restore plan.
- `make restore CHECKPOINT=...` refuses to run without explicit confirmation.
- Volume restore is tested with at least one non-critical service.
- Database restore is tested with a fixture or non-critical database.
- Permissions are validated after restore.
- Health checks run after restore.
- Restore test results are documented.
- CI validates scripts and fixture restore behavior.

---

## End State

When all phases are complete, the homelab will operate as a small but production-grade cloud platform:

- Public services enter only through Cloudflare Tunnel and Traefik.
- Private administration uses Tailscale with ACLs and MagicDNS.
- Services are isolated by Docker networks.
- Secrets are encrypted in Git with SOPS + age.
- CI validates configuration, secrets, images, and security before deployment.
- Production deployment requires explicit manual approval.
- Monitoring, logging, backups, restore tests, and rollback are first-class platform features.
- The structure is ready to scale from one PiKVM V4 to multiple Docker hosts, NAS, NUC, VPS, Nomad, or Kubernetes without redesigning the foundations.





