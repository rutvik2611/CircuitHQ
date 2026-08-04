# Changelog

All notable changes to the CircuitHQ homelab platform will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Phase 15: Documentation Completion — comprehensive docs index, architecture overview, incident response runbook, troubleshooting guide, diagrams index, ADR-0002 (CI/CD strategy), and CHANGELOG

## [0.14.0] — 2026-08-04

### Added
- Phase 14: First real application (example public + private apps with exposure validation)

## [0.13.0] — 2026-08-04

### Added
- Phase 13: Manual deployment pipeline (preflight, deploy, healthcheck, verify-traffic scripts)

## [0.12.0] — 2026-08-04

### Added
- Phase 12: CI validation workflows (GitHub Actions validate + deploy, Woodpecker skeleton)

## [0.11.0] — 2026-08-04

### Added
- Phase 11: Security controls (permission validator, compose security scanner, Trivy/Syft CI scan)

## [0.10.0] — 2026-08-04

### Added
- Phase 10: Backup & restore framework (restic scripts, systemd timer, SOPS-encrypted credentials)

## [0.9.0] — 2026-08-04

### Added
- Phase 9: Logging stack (Loki + Promtail with retention policies)

## [0.8.0] — 2026-08-04

### Added
- Phase 8: Monitoring stack (Prometheus, Grafana, Alertmanager, Node Exporter, cAdvisor, Blackbox, Uptime Kuma)

## [0.7.0] — 2026-08-04

### Added
- Phase 7: Authelia authentication stack with MFA, RBAC, Redis session store

## [0.6.0] — 2026-08-04

### Added
- Phase 6: SOPS + age secrets framework (encrypted secrets in Git)

## [0.5.0] — 2026-08-04

### Added
- Phase 5: Cloudflare Tunnel configuration files

## [0.4.0] — 2026-08-04

### Added
- Phase 4: Traefik reverse proxy with ACME, middleware chains, TLS security

## [0.3.0] — 2026-08-04

### Added
- Phase 3: Docker networks & Compose foundation (shared definitions, volumes)

## [0.2.0] — 2026-08-04

### Added
- Phase 2: Tailscale baseline design files

## [0.1.0] — 2026-08-04

### Added
- Phase 1: Host bootstrap scripts (Docker install, network creation, firewall)

## [0.0.1] — 2026-08-04

### Added
- Phase 0: Project structure and repository bootstrap
- Initial repository skeleton and documentation framework
- Makefile with validation targets
- CI/CD and architecture reference documents