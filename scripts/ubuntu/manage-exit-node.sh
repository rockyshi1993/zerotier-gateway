#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/exit-node.sh"

usage() {
  cat <<'HELP'
Manage a private IPv4 ZeroTier Exit Node without editing configuration files.

Usage:
  manage-exit-node.sh enable [options] [--apply]
  manage-exit-node.sh disable [--apply]
  manage-exit-node.sh status
  manage-exit-node.sh test
  manage-exit-node.sh restore --apply

Options:
  --zerotier-subnet CIDR  ZeroTier IPv4 subnet. Default: .env value or 10.246.77.0/24.
  --ubuntu-zt-ip IP      Ubuntu ZeroTier IPv4 address. Default: .env value or 10.246.77.1.
  --zt-iface NAME        ZeroTier interface; auto-detected from --ubuntu-zt-ip when omitted.
  --wan-iface NAME       Internet egress interface; auto-detected from the default route when omitted.
  --managed-route TEXT   Managed Route hint. Default: 0.0.0.0/0 via <Ubuntu ZeroTier IP>.
  --env PATH             Optional config path; normal users can rely on init-config.sh.
  --dry-run              Alias for preview. No state or system files are changed.
  --apply                Apply the displayed plan. Without it, nothing is changed.
HELP
}

[ "$#" -gt 0 ] || { usage; exit 2; }
action="$1"; shift
case "$action" in enable|disable|status|test|restore) ;; *) usage; exit 2 ;; esac

ZTG_ENV_FILE="$ZTG_ROOT/.env"
ZTG_DRY_RUN=false
zerotier_subnet=""
ubuntu_zt_ip=""
zt_iface=""
wan_iface=""
managed_route=""
apply=false
has_env=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --zerotier-subnet) zerotier_subnet="${2:-}"; shift 2 ;;
    --ubuntu-zt-ip) ubuntu_zt_ip="${2:-}"; shift 2 ;;
    --zt-iface) zt_iface="${2:-}"; shift 2 ;;
    --wan-iface) wan_iface="${2:-}"; shift 2 ;;
    --managed-route) managed_route="${2:-}"; shift 2 ;;
    --env) ZTG_ENV_FILE="${2:-}"; has_env=true; shift 2 ;;
    --dry-run) ZTG_DRY_RUN=true; shift ;;
    --apply) apply=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ztg_log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

if [ "$ZTG_DRY_RUN" = true ]; then
  apply=false
fi

state_path="$(ztg_exit_node_state_path)"
sysctl_path="$(ztg_exit_node_sysctl_path)"
unit_path="$(ztg_exit_node_unit_path)"

load_env_defaults() {
  if [ -f "$ZTG_ENV_FILE" ]; then
    ztg_load_env_file
  elif $has_env; then
    ztg_log_error "Config file not found: $ZTG_ENV_FILE"
    exit 1
  fi
  zerotier_subnet="${zerotier_subnet:-${ZEROTIER_SUBNET:-10.246.77.0/24}}"
  ubuntu_zt_ip="${ubuntu_zt_ip:-${UBUNTU_ZT_IP:-10.246.77.1}}"
  managed_route="${managed_route:-0.0.0.0/0 via ${ubuntu_zt_ip}}"
}

load_state() {
  [ -f "$state_path" ] || { ztg_log_error "Private Exit Node state not found. Run enable first."; exit 1; }
  ztg_validate_state_identity "$state_path" exit-node "$ZTG_EXIT_NODE_OBJECT_NAME" || exit 1
  zerotier_subnet="$(ztg_read_json_scalar "$state_path" zerotierSubnet)"
  ubuntu_zt_ip="$(ztg_read_json_scalar "$state_path" ubuntuZtIp)"
  zt_iface="$(ztg_read_json_scalar "$state_path" ztInterface)"
  wan_iface="$(ztg_read_json_scalar "$state_path" wanInterface)"
  enabled="$(ztg_exit_node_json_boolean "$state_path" enabled)"
  generation="$(ztg_read_json_number "$state_path" generation)"
  previous_runtime="$(ztg_read_json_scalar "$state_path" previousRuntimeForwarding 2>/dev/null || true)"
  managed_route="0.0.0.0/0 via ${ubuntu_zt_ip}"
}

validate_inputs() {
  ztg_exit_node_validate_ipv4_cidr "$zerotier_subnet" || { ztg_log_error 'A valid --zerotier-subnet IPv4 CIDR is required.'; exit 2; }
  ztg_exit_node_validate_ipv4_address "$ubuntu_zt_ip" || { ztg_log_error 'A valid --ubuntu-zt-ip IPv4 address is required.'; exit 2; }
  ztg_exit_node_validate_interface_name "$zt_iface" || { ztg_log_error 'Could not determine a valid ZeroTier interface; pass --zt-iface.'; exit 1; }
  ztg_exit_node_validate_interface_name "$wan_iface" || { ztg_log_error 'Could not determine a valid WAN interface; pass --wan-iface.'; exit 1; }
}

detect_missing_interfaces() {
  if [ -z "$zt_iface" ]; then
    zt_iface="$(ztg_exit_node_detect_zt_interface "$ubuntu_zt_ip" || true)"
  fi
  if [ -z "$wan_iface" ]; then
    wan_iface="$(ztg_exit_node_detect_wan_interface || true)"
  fi
}

print_enable_plan() {
  ztg_log_info "Plan: enable private IPv4 Exit Node; zt=${zt_iface}; wan=${wan_iface}; subnet=${zerotier_subnet}; router=${ubuntu_zt_ip}"
  ztg_exit_node_print_rule_plan "$zerotier_subnet" "$zt_iface" "$wan_iface" | sed 's/^/[PLAN] /'
  printf '[PLAN] write %s with project marker\n' "$sysctl_path"
  printf '[PLAN] write %s with restore command\n' "$unit_path"
  printf '[NEXT] ZeroTier Central Managed Route: %s\n' "$managed_route"
  printf '[NEXT] On Pixel/Android: enable this ZeroTier network and allow default route; keep other VPN/TUN apps off.\n'
  printf '[NEXT] IPv4 check: https://api.ipify.org should show the Ubuntu public egress IP.\n'
  printf '[NEXT] IPv6 check: https://api64.ipify.org may reveal a mobile-carrier IPv6 because this first release is IPv4-only.\n'
}

print_disable_plan() {
  ztg_log_info "Plan: disable private Exit Node and remove only project-owned resources."
  ztg_exit_node_print_rule_plan "$zerotier_subnet" "$zt_iface" "$wan_iface" | sed 's/^/[REMOVE] /'
  printf '[REMOVE] %s if it contains the project marker\n' "$sysctl_path"
  printf '[REMOVE] %s if it contains the project marker\n' "$unit_path"
}

print_status() {
  local current_forwarding="unknown" missing=0
  current_forwarding="$(ztg_exit_node_read_ip_forward 2>/dev/null || printf 'unknown')"
  printf 'enabled=%s\n' "$enabled"
  printf 'zerotierSubnet=%s\n' "$zerotier_subnet"
  printf 'ubuntuZtIp=%s\n' "$ubuntu_zt_ip"
  printf 'ztInterface=%s\n' "$zt_iface"
  printf 'wanInterface=%s\n' "$wan_iface"
  printf 'ipv4Forwarding=%s\n' "$current_forwarding"
  printf 'managedRoute=%s\n' "$managed_route"
  if command -v iptables >/dev/null 2>&1; then
    ztg_exit_node_nat_exists "$zerotier_subnet" "$wan_iface" && printf 'rule.nat=present\n' || { printf 'rule.nat=missing\n'; missing=$((missing + 1)); }
    ztg_exit_node_forward_out_exists "$zerotier_subnet" "$zt_iface" "$wan_iface" && printf 'rule.forwardOut=present\n' || { printf 'rule.forwardOut=missing\n'; missing=$((missing + 1)); }
    ztg_exit_node_forward_in_exists "$zerotier_subnet" "$zt_iface" "$wan_iface" && printf 'rule.forwardIn=present\n' || { printf 'rule.forwardIn=missing\n'; missing=$((missing + 1)); }
  else
    printf 'rule.check=iptables unavailable\n'
  fi
  printf 'pixelStep=ZeroTier One network enabled + Allow Default/Allow Default Route + mobile data\n'
  printf 'ipv4Check=https://api.ipify.org\n'
  printf 'ipv6Check=https://api64.ipify.org\n'
  if [ "${enabled:-false}" = true ] && [ "$missing" -gt 0 ]; then
    ztg_log_error "$missing project iptables rule(s) are missing; run restore --apply or disable --apply."
    return 1
  fi
}

case "$action" in
  enable)
    load_env_defaults
    detect_missing_interfaces
    validate_inputs
    print_enable_plan
    if [ "$apply" != true ]; then
      ztg_log_warn 'Preview only. Re-run with --apply to change forwarding, iptables, state, and the restore unit.'
      exit 0
    fi
    ztg_require_root
    ztg_exit_node_assert_system_tools || exit 1
    ztg_acquire_management_lock
    trap 'ztg_release_management_lock' EXIT
    previous_runtime="$(ztg_exit_node_read_ip_forward 2>/dev/null || printf 'unknown')"
    if [ -f "$state_path" ]; then
      ztg_validate_state_identity "$state_path" exit-node "$ZTG_EXIT_NODE_OBJECT_NAME" || exit 1
      generation="$(( $(ztg_read_json_number "$state_path" generation) + 1 ))"
      old_previous_runtime="$(ztg_read_json_scalar "$state_path" previousRuntimeForwarding 2>/dev/null || true)"
      [ -n "$old_previous_runtime" ] && previous_runtime="$old_previous_runtime"
    else
      generation=1
    fi
    old_state_exists=false; old_state_content=''
    old_sysctl_exists=false; old_sysctl_content=''
    old_unit_exists=false; old_unit_content=''
    nat_preexisting=false; forward_out_preexisting=false; forward_in_preexisting=false
    [ -f "$state_path" ] && { old_state_exists=true; old_state_content="$(<"$state_path")"; }
    [ -f "$sysctl_path" ] && { old_sysctl_exists=true; old_sysctl_content="$(<"$sysctl_path")"; }
    [ -f "$unit_path" ] && { old_unit_exists=true; old_unit_content="$(<"$unit_path")"; }
    ztg_exit_node_nat_exists "$zerotier_subnet" "$wan_iface" && nat_preexisting=true
    ztg_exit_node_forward_out_exists "$zerotier_subnet" "$zt_iface" "$wan_iface" && forward_out_preexisting=true
    ztg_exit_node_forward_in_exists "$zerotier_subnet" "$zt_iface" "$wan_iface" && forward_in_preexisting=true
    rollback_enable() {
      if ! $nat_preexisting && ztg_exit_node_nat_exists "$zerotier_subnet" "$wan_iface"; then
        iptables -t nat -D POSTROUTING -s "$zerotier_subnet" -o "$wan_iface" -m comment --comment "$ZTG_EXIT_NODE_NAT_COMMENT" -j MASQUERADE >/dev/null 2>&1 || true
      fi
      if ! $forward_out_preexisting && ztg_exit_node_forward_out_exists "$zerotier_subnet" "$zt_iface" "$wan_iface"; then
        iptables -D FORWARD -i "$zt_iface" -o "$wan_iface" -s "$zerotier_subnet" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_OUT_COMMENT" -j ACCEPT >/dev/null 2>&1 || true
      fi
      if ! $forward_in_preexisting && ztg_exit_node_forward_in_exists "$zerotier_subnet" "$zt_iface" "$wan_iface"; then
        iptables -D FORWARD -i "$wan_iface" -o "$zt_iface" -d "$zerotier_subnet" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_IN_COMMENT" -j ACCEPT >/dev/null 2>&1 || true
      fi
      if $old_sysctl_exists; then
        ztg_atomic_write "$sysctl_path" "$old_sysctl_content" 0644 || true
      else
        rm -f "$sysctl_path" || true
      fi
      if $old_unit_exists; then
        ztg_atomic_write "$unit_path" "$old_unit_content" 0644 || true
      else
        rm -f "$unit_path" || true
        systemctl disable "$ZTG_EXIT_NODE_UNIT_NAME" >/dev/null 2>&1 || true
      fi
      if $old_state_exists; then
        ztg_atomic_write "$state_path" "$old_state_content" 0600 || true
      else
        rm -f "$state_path" || true
      fi
      systemctl daemon-reload >/dev/null 2>&1 || true
    }
    if ! ztg_exit_node_write_sysctl_file "$sysctl_path"; then
      rollback_enable
      ztg_log_error 'Forwarding sysctl could not be written; changes were rolled back.'
      exit 1
    fi
    if ! ztg_exit_node_apply_rules "$zerotier_subnet" "$zt_iface" "$wan_iface"; then
      rollback_enable
      ztg_log_error 'Project iptables rules could not be applied; changes were rolled back.'
      exit 1
    fi
    manager_path="$(cd "$SCRIPT_DIR" && pwd)/manage-exit-node.sh"
    if ! ztg_exit_node_install_restore_unit "$manager_path" "$unit_path"; then
      rollback_enable
      ztg_log_error 'Restore unit could not be installed; changes were rolled back.'
      exit 1
    fi
    if ! ztg_exit_node_write_state "$state_path" true "$zerotier_subnet" "$ubuntu_zt_ip" "$zt_iface" "$wan_iface" "$previous_runtime" "$generation" "$sysctl_path" "$unit_path"; then
      rollback_enable
      ztg_log_error 'State write failed; changes were rolled back.'
      exit 1
    fi
    ztg_log_info 'Private IPv4 Exit Node enabled.'
    ;;
  disable)
    load_state
    validate_inputs
    print_disable_plan
    if [ "$apply" != true ]; then
      ztg_log_warn 'Preview only. Re-run with --apply to disable the private Exit Node.'
      exit 0
    fi
    ztg_require_root
    ztg_exit_node_assert_system_tools || exit 1
    ztg_acquire_management_lock
    trap 'ztg_release_management_lock' EXIT
    ztg_exit_node_remove_rules "$zerotier_subnet" "$zt_iface" "$wan_iface"
    ztg_exit_node_remove_sysctl_file "$sysctl_path"
    ztg_exit_node_maybe_restore_forwarding_zero "${previous_runtime:-unknown}" "$sysctl_path"
    ztg_exit_node_remove_restore_unit "$unit_path"
    ztg_exit_node_write_state "$state_path" false "$zerotier_subnet" "$ubuntu_zt_ip" "$zt_iface" "$wan_iface" "${previous_runtime:-unknown}" "$((generation + 1))" "$sysctl_path" "$unit_path"
    ztg_log_info 'Private Exit Node disabled; existing proxy, relay, publish, and rate-limit services were not changed.'
    ;;
  status)
    if [ -f "$state_path" ]; then
      load_state
    else
      load_env_defaults
      detect_missing_interfaces || true
      enabled=false
      managed_route="0.0.0.0/0 via ${ubuntu_zt_ip}"
      ztg_log_warn 'Private Exit Node is not enabled by this project.'
    fi
    print_status
    ;;
  test)
    if [ -f "$state_path" ]; then
      load_state
    else
      ztg_log_error 'Private Exit Node is not enabled by this project. Run enable first.'
      exit 1
    fi
    print_status
    cat <<'HELP'

Client acceptance checklist:
  1. ZeroTier Central has Managed Route: 0.0.0.0/0 via the Ubuntu ZeroTier IP.
  2. Pixel/Android is connected to this ZeroTier network.
  3. Pixel/Android has Allow Default / Allow Default Route enabled for this network.
  4. Wi-Fi is off; mobile data is on.
  5. https://api.ipify.org shows the Ubuntu public egress IP.
  6. https://api64.ipify.org is checked separately; this first release is IPv4-only.

Windows note:
  Windows does not automatically use this Exit Node unless you enable Allow Default on that Windows client.
HELP
    ;;
  restore)
    [ "$apply" = true ] || { ztg_log_error 'restore requires --apply.'; exit 2; }
    if [ ! -f "$state_path" ]; then
      ztg_log_warn 'No private Exit Node state found; nothing to restore.'
      exit 0
    fi
    load_state
    [ "$enabled" = true ] || { ztg_log_warn 'Private Exit Node state is disabled; nothing to restore.'; exit 0; }
    validate_inputs
    ztg_require_root
    ztg_exit_node_assert_system_tools || exit 1
    ztg_acquire_management_lock
    trap 'ztg_release_management_lock' EXIT
    ztg_exit_node_write_sysctl_file "$sysctl_path"
    ztg_exit_node_apply_rules "$zerotier_subnet" "$zt_iface" "$wan_iface"
    ztg_log_info 'Private Exit Node rules restored from project state.'
    ;;
esac
