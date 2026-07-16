#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ZTG_ROOT="$ROOT"
source "$ROOT/scripts/ubuntu/lib/logging.sh"
source "$ROOT/scripts/ubuntu/lib/state.sh"
source "$ROOT/scripts/ubuntu/lib/rate-limit.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected=$2 actual=$1)"; }

ztg_validate_ipv4_cidr '10.246.77.30' || fail 'IPv4 should be valid.'
ztg_validate_ipv4_cidr '10.246.77.0/24' || fail 'CIDR should be valid.'
! ztg_validate_ipv4_cidr '10.246.999.1' || fail 'Invalid IPv4 should fail.'
ztg_ipv4_in_cidr '10.246.77.30' '10.246.77.0/24' || fail 'Client should be inside subnet.'
! ztg_ipv4_in_cidr '10.246.78.30' '10.246.77.0/24' || fail 'Client should be outside subnet.'
assert_eq "$(ztg_normalize_rate '20Mbit')" '20mbit' 'Rate normalization failed.'
! ztg_normalize_rate '0mbit' >/dev/null || fail 'Zero rate should fail.'

commands="$(ztg_rate_limit_print_commands 'ztabc123' '10.246.77.30' 10808 '5mbit' '20mbit' 7)"
assert_eq "$(printf '%s\n' "$commands" | wc -l | tr -d ' ')" '4' 'Four directional/protocol filters are required.'
printf '%s' "$commands" | grep -Fq 'ingress' || fail 'Ingress filter missing.'
printf '%s' "$commands" | grep -Fq 'src_ip 10.246.77.30' || fail 'Upload source match missing.'
printf '%s' "$commands" | grep -Fq 'dst_port 10808' || fail 'Upload proxy-port match missing.'
printf '%s' "$commands" | grep -Fq 'egress' || fail 'Egress filter missing.'
printf '%s' "$commands" | grep -Fq 'dst_ip 10.246.77.30' || fail 'Download destination match missing.'
printf '%s' "$commands" | grep -Fq 'src_port 10808' || fail 'Download proxy-port match missing.'
! printf '%s' "$commands" | grep -Eq 'qdisc (del|replace)|filter (del|flush)' || fail 'Generated add plan must not delete/replace qdisc or flush filters.'
grep -Fqx '# Managed-By: zerotier-gateway-rate-limit' "$ROOT/templates/systemd/zerotier-gateway-rate-limit.service.tmpl" || fail 'Restore unit ownership marker missing.'

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
export ZTG_STATE_ROOT="$temp/state"
path="$(ztg_rate_limit_state_path sample)"
ztg_write_rate_limit_state "$path" sample ztabc123 10.246.77.30 10808 5mbit 20mbit 0 zerotier true 1
assert_eq "$(ztg_read_json_scalar "$path" objectType)" 'rate-limit' 'State type mismatch.'
assert_eq "$(ztg_json_boolean "$path" enabled)" 'true' 'Enabled state mismatch.'
assert_eq "$(ztg_allocate_rate_limit_slot "$path")" '0' 'Excluded state slot should be reusable by itself.'
assert_eq "$(ztg_allocate_rate_limit_slot)" '1' 'A new rule should receive the next free slot.'

preview_state="$temp/preview-state"
preview_unit="$temp/systemd"
output="$(ZTG_STATE_ROOT="$preview_state" ZTG_SYSTEMD_DIR="$preview_unit" bash "$ROOT/scripts/ubuntu/manage-rate-limit.sh" add --name demo --client 10.246.77.30 --upload 5mbit --download 20mbit --interface ztabc123 2>&1)"
[ ! -e "$preview_state" ] || fail 'Preview created state.'
[ ! -e "$preview_unit" ] || fail 'Preview created a unit.'
printf '%s' "$output" | grep -Fq 'Preview only' || fail 'Preview message missing.'

manager_source="$(<"$ROOT/scripts/ubuntu/manage-rate-limit.sh")"
printf '%s' "$manager_source" | grep -Fq 'if $exists && [ "$old_enabled" = true ]' || fail 'Disabled-rule rollback guard missing.'
ownership_line="$(grep -nF "grep -Fqx '# Managed-By: zerotier-gateway-rate-limit'" "$ROOT/scripts/ubuntu/manage-rate-limit.sh" | tail -n 1 | cut -d: -f1)"
remove_line="$(grep -nF 'ztg_remove_rate_limit_filters "$interface" "$slot"' "$ROOT/scripts/ubuntu/manage-rate-limit.sh" | tail -n 1 | cut -d: -f1)"
[ "$ownership_line" -lt "$remove_line" ] || fail 'Restore-unit ownership must be checked before removing kernel filters.'

export ZTG_STATE_ROOT="$temp/lock-state"
ztg_acquire_management_lock
if flock -n "$(ztg_management_lock_path)" -c true; then
  fail 'A competing Ubuntu management writer entered the locked critical section.'
fi
ztg_release_management_lock
flock -n "$(ztg_management_lock_path)" -c true || fail 'Ubuntu management lock was not released.'
for manager in manage-rate-limit.sh manage-publish.sh manage-domain.sh; do
  grep -Fq 'ztg_acquire_management_lock' "$ROOT/scripts/ubuntu/$manager" || fail "Shared operation lock missing from $manager."
done

future_path="$temp/future-rate.json"
export ZTG_STATE_ROOT="$(dirname "$path")"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' "$path" > "$future_path"
mv "$future_path" "$path"
set +e
future_output="$(ZTG_STATE_ROOT="$ZTG_STATE_ROOT" bash "$ROOT/scripts/ubuntu/manage-rate-limit.sh" status --name sample 2>&1)"
future_rc=$?
set -e
[ "$future_rc" -ne 0 ] || fail 'Rate manager accepted a future state schema.'
printf '%s' "$future_output" | grep -Fq 'Unsupported or missing state schema' || fail 'Rate manager schema rejection was not diagnostic.'

set +e
allocation_output="$(ztg_allocate_rate_limit_slot 2>&1)"
allocation_rc=$?
set -e
[ "$allocation_rc" -ne 0 ] || fail 'Slot allocation accepted a future state schema.'
printf '%s' "$allocation_output" | grep -Fq 'Unsupported or missing state schema' || fail 'Slot allocation schema rejection was not diagnostic.'

mock_bin="$temp/mock-bin"
mkdir -p "$mock_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$mock_bin/tc"
chmod +x "$mock_bin/tc"
sed 's/"enabled": true/"enabled": false/' "$path" > "$future_path"
mv "$future_path" "$path"
set +e
restore_output="$(PATH="$mock_bin:$PATH" ZTG_DRY_RUN=true ZTG_STATE_ROOT="$ZTG_STATE_ROOT" bash "$ROOT/scripts/ubuntu/manage-rate-limit.sh" restore --apply 2>&1)"
restore_rc=$?
set -e
[ "$restore_rc" -ne 0 ] || fail 'Restore silently skipped a disabled future state schema.'
printf '%s' "$restore_output" | grep -Fq 'Unsupported or missing state schema' || fail 'Restore future-schema rejection was not diagnostic.'

printf 'Rate-limit tests passed.\n'
