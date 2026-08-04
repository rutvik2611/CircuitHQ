# Troubleshooting Guide

Common issues organized by component. See individual runbooks for component-specific troubleshooting tables.

## Proxy (Traefik + Cloudflare Tunnel)

### 404 / 502 / 503 Errors

```
Symptom: Browser shows "404 page not found" or "502 Bad Gateway" or "503 Service Unavailable"
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| No route rule matching Host header | `docker logs circuithq-traefik` | Add correct `traefik.http.routers.<name>.rule` label |
| Service not on proxy network | `docker inspect <container> | jq '.[].NetworkSettings.Networks'` | Add `circuithq-proxy` network to service |
| Service container crashed | `docker ps` | Check logs: `docker logs <container>` |

### Certificate Errors

```
Symptom: Browser shows "Your connection is not private" or "NET::ERR_CERT_COMMON_NAME_INVALID"
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Let's Encrypt rate limit (50 certs/week) | `docker logs circuithq-traefik` | Use staging resolver while testing |
| DNS not pointing to this host | `dig +short <domain>` | Update DNS A/AAAA/CNAME record |
| ACME email not valid | Check `static.yml` | Set valid email in `certificatesResolvers.letsencrypt.acme.email` |

### Tunnel Not Connecting

```
Symptom: Cloudflare Tunnel shows "disconnected" or "offline"
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Invalid tunnel token | `docker logs circuithq-cloudflared` | Regenerate token in Zero Trust dashboard |
| DNS not proxied (grey cloud) | Cloudflare dashboard → DNS | Toggle proxy (orange cloud) on |
| cloudflared not on proxy network | `docker inspect circuithq-cloudflared` | Add `circuithq-proxy` network |

## Auth (Authelia)

### Endless Login Redirect

```
Symptom: Click login, get redirected to auth page, back to app, redirect again
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Session domain mismatch | `configuration.yml` → `session.domain` | Must match the root domain (e.g., `circuithq.internal`) |
| Cookie domain vs Host mismatch | Browser dev tools → Application → Cookies | Set `session.domain` to parent domain |

### MFA Not Prompted

```
Symptom: Logged in with password but not asked for TOTP/WebAuthn
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Policy set to `one_factor` | `access_rules.yml` for that service | Change to `two_factor` |
| MFA not enrolled for user | `users_database.yml` → user's `totp` field | Admin enrolls TOTP or user goes through setup |

### Account Locked Out

```
Symptom: "Authentication failed" even with correct password (after 5 attempts)
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Regulation ban (5 failed attempts in 2 min) | `docker logs authelia` | Wait 5 minutes or restart Authelia |

## Monitoring (Prometheus / Grafana)

### Prometheus Targets Down

```
Symptom: Grafana dashboards show "No data" or targets appear red in Prometheus UI
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Service not on monitoring network | `docker inspect <container>` | Add `circuithq-monitoring` network |
| Service not exposing metrics | `curl http://<service>:<port>/metrics` | Enable metrics endpoint on service |
| Prometheus can't reach host.docker.internal | Docker networking | Use container name instead of host.docker.internal on Linux |

### Grafana Not Loading / 502

```
Symptom: Browser shows 502 when accessing Grafana URL
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Grafana not on proxy network | `docker inspect circuithq-grafana` | Add `circuithq-proxy` network |
| Authelia redirect loop | Browser dev tools → Network | Check `auth-chain` middleware config |

### Disk Full on Monitoring Volume

```
Symptom: Prometheus errors: "no space left on device" or Grafana fails to start
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Retention too long | Check `--storage.tsdb.retention.time` in compose.yml | Reduce to 15 days |
| Loki chunks growing too fast | `docker run --rm -v circuithq-loki-data:/data alpine du -sh /data` | Shorten retention or increase log rotation frequency |

## Logging (Loki + Promtail)

### No Logs in Grafana

```
Symptom: Loki datasource shows "No logs found" or empty results
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Promtail → Loki connection | `docker logs circuithq-promtail` | Check `clients.url` in Promtail config |
| Promtail not reading Docker logs | `docker logs circuithq-promtail` | Verify `/var/lib/docker/containers/` bind mount |
| Wrong label filter in LogQL | Check label names: `http://localhost:3100/loki/api/v1/labels` | Use correct label names |

### High Memory Usage by Loki

```
Symptom: Loki consuming >2GB RAM
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Too many label combinations | Loki metrics dashboard | Reduce cardinality (fewer unique label values) |
| Ingestion rate too high | `curl http://localhost:3100/metrics` | Increase `max_streams_per_user` or reduce log sources |

## Secrets & Encryption

### SOPS: "could not find an age key"

```
Symptom: sops --decrypt fails with "could not find an age key"
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| keys.txt missing | `ls -la ~/.config/sops/age/keys.txt` | Run `age-keygen -o ~/.config/sops/age/keys.txt` |
| Wrong env var | `echo $SOPS_AGE_KEY_FILE` | Export: `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt` |
| Wrong permissions | `stat -f %Lp ~/.config/sops/age/keys.txt` | `chmod 600 ~/.config/sops/age/keys.txt` |

### SOPS: "age key not matching"

```
Symptom: sops --decrypt says key doesn't match file
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| `.sops.yaml` has wrong public key | Check `age:` in `.sops.yaml` | Run `sops updatekeys -y secrets/**/*.sops.yaml` |
| Key was rotated but files not updated | Compare keys | Update `.sops.yaml` and re-encrypt |

## Backup & Restore

### Backups Failing

```
Symptom: backup.sh exits with error, or snapshots not appearing
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Repository not initialized | `restic list locks` | Run `restic init` |
| Wrong password | `RESTIC_PASSWORD` mismatch | Verify SOPS decryption |
| S3 endpoint unreachable | `curl -I <s3-endpoint>` | Check network and DNS |

### Restore Test Failing

```
Symptom: restore-test.sh exits 1
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Repo files changed location | `ls` expected files in latest snapshot | Update `restore-test.sh` check paths |
| Snapshot empty or corrupt | `restic stats --latest` | Check backup script output |

## Docker Host

### Docker Daemon Won't Start

```
Symptom: `docker ps` fails with "Cannot connect to the Docker daemon"
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| OrbStack/Docker Desktop not running | System tray icon | Start the Docker runtime |
| Colima not started | `colima status` | `colima start` |

### Port Conflict on 80/443

```
Symptom: Traefik won't start, "port is already allocated"
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Another service using port | `lsof -i :80 -i :443` | Stop conflicting service (e.g., `sudo apachectl stop`) |
| OrbStack reserved ports | Check OrbStack settings | Disable OrbStack port forwarding on 80/443 |

### Disk Space Low

```
Symptom: "no space left on device" when pulling images or writing logs
```

| Likely Cause | Check | Fix |
|-------------|-------|-----|
| Docker unused images/volumes | `docker system df` | `docker system prune -a` |
| Loki logs filling disk | `du -sh /var/lib/docker/volumes/circuithq-loki-data/_data` | Reduce log retention |
| Old Docker images | `docker image ls` | `docker image prune -a` |

## General Diagnostic Commands

```bash
# Quick health check
docker ps --format "table {{.Names}}\t{{.Status}}" | grep circuithq

# Check all networks
docker network ls | grep circuithq

# Check all volumes
docker volume ls | grep circuithq

# Follow all composable stack logs
for d in stacks/proxy stacks/auth stacks/monitoring stacks/logging; do
  echo "=== $d ==="
  docker compose -f "$d/compose.yml" ps
done

# Full validation
make validate
```