#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ZTG_ROOT="$ROOT"
source "$ROOT/scripts/ubuntu/lib/logging.sh"
source "$ROOT/scripts/ubuntu/lib/state.sh"
source "$ROOT/scripts/ubuntu/lib/exit-node.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() { printf '%s' "$1" | grep -Fq "$2" || fail "$3"; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected=$2 actual=$1)"; }

ztg_exit_node_validate_ipv4_cidr '10.246.77.0/24' || fail 'Valid ZeroTier subnet rejected.'
ztg_exit_node_validate_ipv4_address '10.246.77.1' || fail 'Valid Ubuntu ZeroTier IP rejected.'
! ztg_exit_node_validate_ipv4_address '10.246.77.1/24' || fail 'CIDR accepted where host IP is required.'
! ztg_exit_node_validate_ipv4_cidr '10.246.999.0/24' || fail 'Invalid IPv4 subnet accepted.'
ztg_exit_node_validate_interface_name 'ztabc123' || fail 'Valid ZeroTier interface rejected.'
! ztg_exit_node_validate_interface_name '../eth0' || fail 'Path-like interface name accepted.'

plan="$(ztg_exit_node_print_rule_plan '10.246.77.0/24' 'ztabc123' 'eth0')"
assert_contains "$plan" 'sysctl -w net.ipv4.ip_forward=1' 'Forwarding command missing.'
assert_contains "$plan" 'iptables -t nat -A POSTROUTING -s 10.246.77.0/24 -o eth0' 'NAT command missing.'
assert_contains "$plan" 'ztg-exit-node-nat' 'NAT ownership comment missing.'
assert_contains "$plan" 'ztg-exit-node-forward-out' 'Forward-out ownership comment missing.'
assert_contains "$plan" 'ztg-exit-node-forward-in' 'Forward-in ownership comment missing.'
! printf '%s' "$plan" | grep -Eq 'iptables (-F|--flush)|iptables-save|netfilter-persistent|ufw' || fail 'Exit Node plan must not flush or globally save firewall state.'

template="$(<"$ROOT/templates/systemd/zerotier-gateway-exit-node.service.tmpl")"
assert_contains "$template" '# Managed-By: zerotier-gateway-exit-node' 'Restore unit marker missing.'
assert_contains "$template" '/usr/bin/env bash "{{EXIT_NODE_MANAGER_PATH}}" restore --apply' 'Restore unit must invoke the manager through bash.'

grep -Fq '"exit-node"' "$ROOT/config/state-schema-v1.json" || fail 'State schema enum does not include exit-node.'

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
export ZTG_STATE_ROOT="$temp/state"
export ZTG_SYSCTL_DIR="$temp/sysctl"
export ZTG_SYSTEMD_DIR="$temp/systemd"

state_path="$(ztg_exit_node_state_path)"
sysctl_path="$(ztg_exit_node_sysctl_path)"
unit_path="$(ztg_exit_node_unit_path)"
ztg_exit_node_write_state "$state_path" true '10.246.77.0/24' '10.246.77.1' 'ztabc123' 'eth0' '0' 1 "$sysctl_path" "$unit_path"
assert_eq "$(ztg_read_json_scalar "$state_path" objectType)" 'exit-node' 'State type mismatch.'
assert_eq "$(ztg_exit_node_json_boolean "$state_path" enabled)" 'true' 'Enabled state mismatch.'
assert_eq "$(ztg_read_json_scalar "$state_path" objectName)" 'default' 'State object name mismatch.'

preview_state="$temp/preview-state"
preview_sysctl="$temp/preview-sysctl"
preview_units="$temp/preview-units"
preview_output="$(ZTG_STATE_ROOT="$preview_state" ZTG_SYSCTL_DIR="$preview_sysctl" ZTG_SYSTEMD_DIR="$preview_units" bash "$ROOT/scripts/ubuntu/manage-exit-node.sh" enable --zerotier-subnet 10.246.77.0/24 --ubuntu-zt-ip 10.246.77.1 --zt-iface ztabc123 --wan-iface eth0 2>&1)"
[ ! -e "$preview_state" ] || fail 'Preview created state.'
[ ! -e "$preview_sysctl" ] || fail 'Preview created sysctl file.'
[ ! -e "$preview_units" ] || fail 'Preview created restore unit.'
assert_contains "$preview_output" 'Preview only' 'Enable preview message missing.'
assert_contains "$preview_output" 'ZeroTier Central Managed Route: 0.0.0.0/0 via 10.246.77.1' 'Central route hint missing.'
assert_contains "$preview_output" 'api64.ipify.org' 'IPv6 leak check hint missing.'

disable_output="$(ZTG_STATE_ROOT="$ZTG_STATE_ROOT" ZTG_SYSCTL_DIR="$ZTG_SYSCTL_DIR" ZTG_SYSTEMD_DIR="$ZTG_SYSTEMD_DIR" bash "$ROOT/scripts/ubuntu/manage-exit-node.sh" disable 2>&1)"
assert_contains "$disable_output" 'Preview only' 'Disable preview message missing.'
assert_contains "$disable_output" 'remove only project-owned resources' 'Disable ownership boundary missing.'

future_path="$temp/future-exit-node.json"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' "$state_path" > "$future_path"
mv "$future_path" "$state_path"
set +e
future_output="$(ZTG_STATE_ROOT="$ZTG_STATE_ROOT" ZTG_SYSCTL_DIR="$ZTG_SYSCTL_DIR" ZTG_SYSTEMD_DIR="$ZTG_SYSTEMD_DIR" bash "$ROOT/scripts/ubuntu/manage-exit-node.sh" status 2>&1)"
future_rc=$?
set -e
[ "$future_rc" -ne 0 ] || fail 'Exit Node manager accepted a future state schema.'
assert_contains "$future_output" 'Unsupported or missing state schema' 'Future schema rejection was not diagnostic.'

manager_source="$(<"$ROOT/scripts/ubuntu/manage-exit-node.sh")"
lib_source="$(<"$ROOT/scripts/ubuntu/lib/exit-node.sh")"
! printf '%s\n%s' "$manager_source" "$lib_source" | grep -Eq 'iptables[[:space:]]+(-F|--flush)|iptables-save|netfilter-persistent[[:space:]]+save|ufw[[:space:]]+allow' || fail 'Exit Node implementation contains global firewall mutation.'
assert_contains "$manager_source" 'Private Exit Node disabled; existing proxy, relay, publish, and rate-limit services were not changed.' 'Compatibility success message missing.'

printf 'Exit-node tests passed.\n'
