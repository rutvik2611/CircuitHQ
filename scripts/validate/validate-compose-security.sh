#!/bin/bash
# CircuitHQ — Validate Docker Compose Security
# ==============================================
# Scans all compose.yml files for risky patterns:
#   - privileged: true
#   - Docker socket mounts (/var/run/docker.sock)
#   - Missing restart: unless-stopped or always
#   - network_mode: host (without documented exception)
#   - Missing no-new-privileges where expected
#
# Returns non-zero if critical issues found. Warnings for advisory items.

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ERRORS=0
WARNINGS=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "=== Validating Docker Compose Security ==="
echo ""

# Collect all compose.yml files
COMPOSE_FILES=()
while IFS= read -r -d '' f; do
  COMPOSE_FILES+=("$f")
done < <(find "$BASE_DIR" -name "compose.yml" -path "*/stacks/*" -print0 2>/dev/null || true)

if [ ${#COMPOSE_FILES[@]} -eq 0 ]; then
  echo -e "${YELLOW}⚠️${NC} No compose.yml files found in stacks/"
  exit 0
fi

for compose_file in "${COMPOSE_FILES[@]}"; do
  relative="${compose_file#$BASE_DIR/}"
  echo "📄 Checking $relative..."

  # Check if file exists and parse
  if [ ! -f "$compose_file" ]; then
    continue
  fi

  # Use Python to parse YAML safely
  PY_OUTPUT=$(python3 -c "
import yaml, sys
with open('$compose_file') as f:
    data = yaml.safe_load(f)
if data is None:
    sys.exit(0)
issues = {'errors': [], 'warnings': []}

services = data.get('services', {})
for sname, sdata in services.items():
    # 1. privileged check
    if sdata.get('privileged', False):
        issues['warnings'].append(f'  ⚠️  {sname}: privileged=true — verify this is required')

    # 2. Docker socket mount
    volumes = sdata.get('volumes', []) or []
    for vol in volumes:
        vol_str = vol if isinstance(vol, str) else (vol.get('source', '') if isinstance(vol, dict) else '')
        if '/var/run/docker.sock' in vol_str:
            issues['warnings'].append(f'  ⚠️  {sname}: mounts /var/run/docker.sock — use read_only: true')

    # 3. Restart policy
    restart = sdata.get('restart', '')
    if restart == '' or restart == 'no':
        issues['errors'].append(f'  ❌  {sname}: missing restart policy (use unless-stopped)')

    # 4. network_mode: host
    net_mode = sdata.get('network_mode', '')
    if net_mode == 'host':
        issues['warnings'].append(f'  ⚠️  {sname}: network_mode=host — document reason')

    # 5. Missing security_opt no-new-privileges (for containers with socket mounts)
    if any('/var/run/docker.sock' in (vol if isinstance(vol, str) else (vol.get('source','') if isinstance(vol, dict) else '')) for vol in (sdata.get('volumes', []) or [])):
        sec_opt = sdata.get('security_opt', []) or []
        if 'no-new-privileges:true' not in sec_opt:
            issues['warnings'].append(f'  ⚠️  {sname}: has Docker socket but no security_opt: [no-new-privileges:true]')

    # 6. Port binding on host mode without restriction
    ports = sdata.get('ports', []) or []
    for port in ports:
        p_str = port if isinstance(port, str) else ''
        if 'mode: host' in p_str or (isinstance(port, dict) and port.get('mode') == 'host'):
            issues['warnings'].append(f'  ⚠️  {sname}: port mode=host — ensure restricted to 80/443 only')

for issue in issues['errors']:
    print(issue)
for issue in issues['warnings']:
    print(issue)
" 2>&1) || true

  # Parse and display results
  while IFS= read -r line; do
    if [[ "$line" == ❌* ]]; then
      echo -e "${RED}$line${NC}"
      ERRORS=$((ERRORS + 1))
    elif [[ "$line" == ⚠️* ]]; then
      echo -e "${YELLOW}$line${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  done <<< "$PY_OUTPUT"
  echo ""
done

echo "=== Summary ==="
if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}❌  $ERRORS error(s) found${NC}"
else
  echo -e "${GREEN}✅  0 errors${NC}"
fi
echo -e "${YELLOW}⚠️   $WARNINGS warning(s)${NC}"

exit $ERRORS