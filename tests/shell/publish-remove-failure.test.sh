#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

state_root="$temporary/state"
unit_root="$temporary/systemd"
mock_bin="$temporary/bin"
mkdir -p "$state_root" "$unit_root" "$mock_bin"

cat > "$mock_bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
if [ "${1:-}" = daemon-reload ]; then exit 1; fi
exit 0
MOCK
chmod +x "$mock_bin/systemctl"

cat > "$state_root/publish-ip-demo.json" <<'STATE'
{
  "schemaVersion": 1,
  "owner": "zerotier-gateway",
  "objectType": "publish-ip",
  "objectName": "demo",
  "listenIp": "0.0.0.0",
  "listenPort": "18080",
  "targetIp": "10.246.77.30",
  "targetPort": "8080",
  "sourceCidr": "",
  "firewallMode": "none",
  "generation": 1
}
STATE
printf '%s\n' '# Managed-By: zerotier-gateway-publish-demo' > "$unit_root/zerotier-gateway-publish-demo.socket"
printf '%s\n' '# Managed-By: zerotier-gateway-publish-demo' > "$unit_root/zerotier-gateway-publish-demo.service"
before_socket="$(<"$unit_root/zerotier-gateway-publish-demo.socket")"
before_service="$(<"$unit_root/zerotier-gateway-publish-demo.service")"
before_state="$(<"$state_root/publish-ip-demo.json")"

set +e
output="$(PATH="$mock_bin:$PATH" ZTG_DRY_RUN=true ZTG_STATE_ROOT="$state_root" ZTG_SYSTEMD_DIR="$unit_root" \
  bash "$ROOT/scripts/ubuntu/manage-publish.sh" remove --name demo --apply 2>&1)"
result=$?
set -e

[ "$result" -ne 0 ] || { printf 'FAIL: injected daemon-reload failure was accepted.\n' >&2; exit 1; }
[ -f "$unit_root/zerotier-gateway-publish-demo.socket" ] || { printf 'FAIL: socket was not restored.\n' >&2; exit 1; }
[ -f "$unit_root/zerotier-gateway-publish-demo.service" ] || { printf 'FAIL: service was not restored.\n' >&2; exit 1; }
[ -f "$state_root/publish-ip-demo.json" ] || { printf 'FAIL: state was not restored.\n' >&2; exit 1; }
[ "$(<"$unit_root/zerotier-gateway-publish-demo.socket")" = "$before_socket" ] || { printf 'FAIL: restored socket changed.\n' >&2; exit 1; }
[ "$(<"$unit_root/zerotier-gateway-publish-demo.service")" = "$before_service" ] || { printf 'FAIL: restored service changed.\n' >&2; exit 1; }
[ "$(<"$state_root/publish-ip-demo.json")" = "$before_state" ] || { printf 'FAIL: restored state changed.\n' >&2; exit 1; }
printf '%s' "$output" | grep -Fq 'project files, state, firewall, and service were restored' || { printf 'FAIL: recovery diagnostic missing.\n' >&2; exit 1; }

printf 'Publish remove failure test passed.\n'
