#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ZTG_ROOT="$ROOT"
source "$ROOT/scripts/ubuntu/lib/logging.sh"
source "$ROOT/scripts/ubuntu/lib/state.sh"
source "$ROOT/scripts/ubuntu/lib/rate-limit.sh"
source "$ROOT/scripts/ubuntu/lib/publish.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() { printf '%s' "$1" | grep -Fq "$2" || fail "$3"; }

ztg_validate_publish_name site1 || fail 'Valid mapping name rejected.'
! ztg_validate_publish_name '../site' || fail 'Path-like mapping name accepted.'
ztg_validate_listen_address '0.0.0.0' || fail 'Wildcard listen rejected.'
ztg_validate_listen_address '203.0.113.10' || fail 'IPv4 listen rejected.'
! ztg_validate_listen_address '203.0.113.0/24' || fail 'Listen CIDR accepted.'

ufw() {
  if [ "${1:-}" = status ] && [ "${2:-}" = numbered ]; then
    cat <<'STATUS'
Status: active
[ 1] 18080/tcp ALLOW IN Anywhere # zerotier-gateway-publish-site
[ 2] 18081/tcp ALLOW IN Anywhere # zerotier-gateway-publish-site2
STATUS
    return 0
  fi
  return 1
}
[ "$(ztg_ufw_rule_numbers 'zerotier-gateway-publish-site' | paste -sd, -)" = 1 ] || fail 'UFW marker matching crossed an object-name boundary.'
unset -f ufw

socket="$(ztg_render_publish_socket site1 0.0.0.0 18080)"
service="$(ztg_render_publish_service site1 10.246.77.30 3000 /usr/lib/systemd/systemd-socket-proxyd)"
assert_contains "$socket" '# Managed-By: zerotier-gateway-publish-site1' 'Socket ownership marker missing.'
assert_contains "$socket" 'ListenStream=0.0.0.0:18080' 'Listen address missing.'
assert_contains "$socket" 'MaxConnections=256' 'Connection budget missing.'
assert_contains "$service" '10.246.77.30:3000' 'Target missing.'
assert_contains "$service" 'User=nobody' 'Unprivileged service user missing.'

temp="$(mktemp -d)"; trap 'rm -rf "$temp"' EXIT
preview_state="$temp/state"; preview_units="$temp/units"
output="$(ZTG_STATE_ROOT="$preview_state" ZTG_SYSTEMD_DIR="$preview_units" bash "$ROOT/scripts/ubuntu/manage-publish.sh" add-ip --name demo --listen-port 18080 --target-ip 10.246.77.30 --target-port 3000 2>&1)"
[ ! -e "$preview_state" ] || fail 'Preview created state.'
[ ! -e "$preview_units" ] || fail 'Preview created units.'
assert_contains "$output" 'Preview only' 'Preview message missing.'
assert_contains "$output" 'TCP only' 'Protocol boundary missing.'

export ZTG_STATE_ROOT="$temp/state-write"
path="$(ztg_publish_state_path demo)"
ztg_write_publish_state "$path" demo 0.0.0.0 18080 10.246.77.30 3000 '' 1 none
[ "$(ztg_read_json_scalar "$path" objectType)" = publish-ip ] || fail 'State type mismatch.'
[ "$(ztg_read_json_scalar "$path" targetIp)" = 10.246.77.30 ] || fail 'Target state mismatch.'

mock_bin="$temp/mock-bin"; mkdir -p "$mock_bin"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = status ]; then printf "Status: inactive\\n"; exit 0; fi\nprintf "unexpected mutation\\n" >> "${ZTG_UFW_MUTATION_LOG:?}"\n' > "$mock_bin/ufw"
chmod +x "$mock_bin/ufw"
export ZTG_UFW_MUTATION_LOG="$temp/ufw-mutations"
set +e
PATH="$mock_bin:$PATH" ztg_add_owned_ufw_rule demo 0.0.0.0 18080 '' >/dev/null 2>&1
ufw_rc=$?
set -e
[ "$ufw_rc" -eq 2 ] || fail 'Inactive UFW should be treated as an unmanaged firewall layer.'
[ ! -e "$ZTG_UFW_MUTATION_LOG" ] || fail 'Inactive UFW received a dormant allow rule.'

future_path="$temp/future-publish.json"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' "$path" > "$future_path"
mv "$future_path" "$path"
set +e
future_output="$(ZTG_STATE_ROOT="$ZTG_STATE_ROOT" ZTG_SYSTEMD_DIR="$preview_units" bash "$ROOT/scripts/ubuntu/manage-publish.sh" status --name demo 2>&1)"
future_rc=$?
set -e
[ "$future_rc" -ne 0 ] || fail 'Publish manager accepted a future state schema.'
assert_contains "$future_output" 'Unsupported or missing state schema' 'Publish manager schema rejection was not diagnostic.'

printf 'Publish tests passed.\n'
