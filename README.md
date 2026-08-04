# Homelab Platform Blueprint
This folder contains the production-grade homelab platform design split into four smaller Markdown files for easier reading and smaller-model implementation sessions.
## Files
1. [`01_ARCHITECTURE_NETWORKING.md`](01_ARCHITECTURE_NETWORKING.md)  
   Architecture, diagrams, Tailscale, Docker networks, Traefik, and service design.
2. [`02_DELIVERY_CICD_TESTING.md`](02_DELIVERY_CICD_TESTING.md)  
   CI/CD, deployment pipeline, rollback, testing, M3 Mac workflow, and detailed GitHub Actions design.
3. [`03_OPERATIONS_SECURITY_BACKUP.md`](03_OPERATIONS_SECURITY_BACKUP.md)  
   Backup, restore, monitoring, logging, security, secrets, observability, documentation, disaster recovery, risks, operational checklists, and one-shot restore.
4. [`04_IMPLEMENTATION_ROADMAP_REFERENCE.md`](04_IMPLEMENTATION_ROADMAP_REFERENCE.md)  
   Directory structure, technology comparisons, recommended stack, scaling roadmap, implementation phases, small-model prompts, final architecture, and end state.
## Source archive
The original large file is retained as:
- [`HOMELAB_PLATFORM_BLUEPRINT.md`](HOMELAB_PLATFORM_BLUEPRINT.md)
Use the split files for day-to-day work. Keep the original only as a source/archive unless you later decide to remove it.
## Suggested reading order
```text
01_ARCHITECTURE_NETWORKING.md
   -> 02_DELIVERY_CICD_TESTING.md
   -> 03_OPERATIONS_SECURITY_BACKUP.md
   -> 04_IMPLEMENTATION_ROADMAP_REFERENCE.md
```
