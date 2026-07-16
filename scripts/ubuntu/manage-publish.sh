#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  add-domain|update-domain|list-domains|status-domain|test-domain|remove-domain)
    exec bash "$SCRIPT_DIR/manage-domain.sh" "$@"
    ;;
esac
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/rate-limit.sh"
source "$SCRIPT_DIR/lib/publish.sh"

usage() {
  cat <<'HELP'
Publish a ZeroTier TCP service through this Ubuntu server; no configuration-file editing is required.

Usage:
  manage-publish.sh add-ip|update-ip [options] [--apply]
  manage-publish.sh list
  manage-publish.sh status|test --name NAME
  manage-publish.sh remove --name NAME [--apply]
  manage-publish.sh add-domain|update-domain|list-domains|status-domain|test-domain|remove-domain ...

Options:
  --name NAME               Mapping name.
  --listen-ip IP            Public listen address. Default: 0.0.0.0.
  --listen-port PORT        Public TCP port.
  --target-ip ZT_IP         ZeroTier target address.
  --target-port PORT        Target TCP port.
  --source-cidr CIDR        Optional source restriction; one CIDR in the first release.
  --zerotier-subnet CIDR    Target validation subnet. Default: 10.246.77.0/24.
  --apply                   Apply the displayed plan. Without it, no system change occurs.
HELP
}

[ "$#" -gt 0 ] || { usage; exit 2; }
action="$1"; shift
case "$action" in add-ip|update-ip|list|status|test|remove) ;; *) usage; exit 2 ;; esac

name='' listen_ip='' listen_port='' target_ip='' target_port='' source_cidr='' zerotier_subnet='10.246.77.0/24' apply=false
has_listen_ip=false; has_listen_port=false; has_target_ip=false; has_target_port=false; has_source_cidr=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --listen-ip) listen_ip="${2:-}"; has_listen_ip=true; shift 2 ;;
    --listen-port) listen_port="${2:-}"; has_listen_port=true; shift 2 ;;
    --target-ip) target_ip="${2:-}"; has_target_ip=true; shift 2 ;;
    --target-port) target_port="${2:-}"; has_target_port=true; shift 2 ;;
    --source-cidr) source_cidr="${2:-}"; has_source_cidr=true; shift 2 ;;
    --zerotier-subnet) zerotier_subnet="${2:-}"; shift 2 ;;
    --apply) apply=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ztg_log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

state_root="$(ztg_state_root)"
unit_dir="${ZTG_SYSTEMD_DIR:-/etc/systemd/system}"

require_name() {
  if [ -z "$name" ] && [ -t 0 ]; then read -r -p 'Mapping name: ' name; fi
  ztg_validate_publish_name "$name" || { ztg_log_error 'A valid --name is required.'; exit 2; }
}

load_state() {
  local path="$1"
  [ -f "$path" ] || { ztg_log_error "Mapping not found: $name"; exit 1; }
  ztg_validate_state_identity "$path" publish-ip "$name" || exit 1
  listen_ip="$(ztg_read_json_scalar "$path" listenIp)"; listen_port="$(ztg_read_json_scalar "$path" listenPort)"
  target_ip="$(ztg_read_json_scalar "$path" targetIp)"; target_port="$(ztg_read_json_scalar "$path" targetPort)"
  source_cidr="$(ztg_read_json_scalar "$path" sourceCidr)"; firewall_mode="$(ztg_read_json_scalar "$path" firewallMode)"
  generation="$(sed -nE 's/^[[:space:]]*"generation"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$path" | head -n 1)"
}

if [ "$action" = list ]; then
  found=false
  for file in "$state_root"/publish-ip-*.json; do
    [ -f "$file" ] || continue; found=true
    state_name="$(basename "$file")"; state_name="${state_name#publish-ip-}"; state_name="${state_name%.json}"
    ztg_validate_state_identity "$file" publish-ip "$state_name" || exit 1
    printf '%-20s %-21s -> %s:%s\n' "$(ztg_read_json_scalar "$file" objectName)" \
      "$(ztg_read_json_scalar "$file" listenIp):$(ztg_read_json_scalar "$file" listenPort)" \
      "$(ztg_read_json_scalar "$file" targetIp)" "$(ztg_read_json_scalar "$file" targetPort)"
  done
  $found || ztg_log_warn 'No public IP mappings are configured.'
  exit 0
fi

require_name
state_path="$(ztg_publish_state_path "$name")"
unit_base="$(ztg_publish_unit_base "$name")"
socket_path="$unit_dir/$unit_base.socket"
service_path="$unit_dir/$unit_base.service"
case "$action" in
  add-ip|update-ip|remove)
    if [ "$apply" = true ]; then
      ztg_require_root
      ztg_acquire_management_lock
      trap 'ztg_release_management_lock' EXIT
    fi
    ;;
esac

case "$action" in
  add-ip|update-ip)
    exists=false
    requested_listen_ip="$listen_ip"; requested_listen_port="$listen_port"; requested_target_ip="$target_ip"; requested_target_port="$target_port"; requested_source_cidr="$source_cidr"
    if [ -f "$state_path" ]; then
      exists=true; load_state "$state_path"
      old_listen_ip="$listen_ip"; old_listen_port="$listen_port"; old_target_ip="$target_ip"; old_target_port="$target_port"; old_source_cidr="$source_cidr"; old_firewall_mode="$firewall_mode"
      $has_listen_ip && listen_ip="$requested_listen_ip"; $has_listen_port && listen_port="$requested_listen_port"
      $has_target_ip && target_ip="$requested_target_ip"; $has_target_port && target_port="$requested_target_port"
      $has_source_cidr && source_cidr="$requested_source_cidr"
    else
      listen_ip="${requested_listen_ip:-0.0.0.0}"; listen_port="$requested_listen_port"; target_ip="$requested_target_ip"; target_port="$requested_target_port"; source_cidr="$requested_source_cidr"
      generation=1; firewall_mode=none
    fi
    if [ "$action" = add-ip ] && $exists; then ztg_log_error "Mapping already exists: $name"; exit 1; fi
    if [ "$action" = update-ip ] && ! $exists; then ztg_log_error "Mapping not found: $name"; exit 1; fi
    if [ -t 0 ]; then
      [ -n "$listen_port" ] || read -r -p 'Public TCP port: ' listen_port
      [ -n "$target_ip" ] || read -r -p 'ZeroTier target IP: ' target_ip
      [ -n "$target_port" ] || read -r -p 'Target TCP port: ' target_port
    fi
    ztg_validate_listen_address "$listen_ip" || { ztg_log_error 'Invalid listen IPv4 address.'; exit 2; }
    ztg_validate_proxy_port "$listen_port" || { ztg_log_error 'Invalid listen port.'; exit 2; }
    ztg_validate_ipv4_cidr "$target_ip" && [[ "$target_ip" != */* ]] || { ztg_log_error 'Invalid target IPv4 address.'; exit 2; }
    ztg_ipv4_in_cidr "$target_ip" "$zerotier_subnet" || { ztg_log_error "$target_ip is outside ZeroTier subnet $zerotier_subnet."; exit 1; }
    ztg_validate_proxy_port "$target_port" || { ztg_log_error 'Invalid target port.'; exit 2; }
    if [ -n "$source_cidr" ]; then ztg_validate_ipv4_cidr "$source_cidr" || { ztg_log_error 'Invalid source CIDR.'; exit 2; }; fi
    if ! $exists && [ "$(ztg_count_publish_states)" -ge "$ZTG_PUBLISH_MAX_MAPPINGS" ]; then ztg_log_error 'The 64-mapping first-release capacity has been reached.'; exit 1; fi
    socket_proxyd="$(ztg_socket_proxyd_path 2>/dev/null || printf '/usr/lib/systemd/systemd-socket-proxyd')"
    socket_content="$(ztg_render_publish_socket "$name" "$listen_ip" "$listen_port")"
    service_content="$(ztg_render_publish_service "$name" "$target_ip" "$target_port" "$socket_proxyd")"
    ztg_log_info "Plan: $action $name; ${listen_ip}:${listen_port} -> ${target_ip}:${target_port}; source=${source_cidr:-any}; TCP only"
    if [ "$apply" != true ]; then
      printf '%s\n---\n%s\n' "$socket_content" "$service_content"
      ztg_log_warn 'Preview only. Re-run with --apply to create and start this mapping.'
      exit 0
    fi
    ztg_require_root
    command -v systemctl >/dev/null || { ztg_log_error 'systemctl is required.'; exit 1; }
    socket_proxyd="$(ztg_socket_proxyd_path)" || { ztg_log_error 'systemd-socket-proxyd was not found.'; exit 1; }
    socket_content="$(ztg_render_publish_socket "$name" "$listen_ip" "$listen_port")"
    service_content="$(ztg_render_publish_service "$name" "$target_ip" "$target_port" "$socket_proxyd")"
    if $exists; then
      ztg_is_owned_publish_unit "$socket_path" "$name" && ztg_is_owned_publish_unit "$service_path" "$name" || { ztg_log_error 'Existing unit ownership could not be proven.'; exit 1; }
      if [ "$old_firewall_mode" = ufw ]; then ztg_assert_owned_ufw_rule "$(ztg_publish_marker "$name")" || exit 1; fi
    elif [ -e "$socket_path" ] || [ -e "$service_path" ]; then ztg_log_error 'A same-name unit already exists and was not changed.'; exit 1; fi
    if { ! $exists || [ "$listen_ip:$listen_port" != "$old_listen_ip:$old_listen_port" ]; } && ztg_publish_port_occupied "$listen_ip" "$listen_port"; then ztg_log_error "TCP ${listen_ip}:${listen_port} is already occupied."; exit 1; fi
    old_socket=''; old_service=''; old_state=''
    if $exists; then old_socket="$(<"$socket_path")"; old_service="$(<"$service_path")"; old_state="$(<"$state_path")"; fi
    mkdir -p "$unit_dir"
    candidate_dir="$(mktemp -d)"; trap 'rm -rf "$candidate_dir"' EXIT
    printf '%s\n' "$socket_content" > "$candidate_dir/$unit_base.socket"
    printf '%s\n' "$service_content" > "$candidate_dir/$unit_base.service"
    if command -v systemd-analyze >/dev/null; then systemd-analyze verify "$candidate_dir/$unit_base.socket" "$candidate_dir/$unit_base.service" >/dev/null; fi
    if $exists; then
      if ! ztg_remove_owned_ufw_rule "$(ztg_publish_marker "$name")"; then
        ztg_remove_owned_ufw_rule "$(ztg_publish_marker "$name")" || true
        if [ "$old_firewall_mode" = ufw ]; then ztg_add_owned_ufw_rule "$name" "$old_listen_ip" "$old_listen_port" "$old_source_cidr" || ztg_log_error 'The prior marked UFW rule also could not be fully restored.'; fi
        ztg_log_error 'Existing marked UFW rule could not be replaced safely; unit files, service, and state were not changed.'
        exit 1
      fi
      if ! systemctl disable --now "$unit_base.socket" >/dev/null 2>&1; then
        if [ "$old_firewall_mode" = ufw ]; then ztg_add_owned_ufw_rule "$name" "$old_listen_ip" "$old_listen_port" "$old_source_cidr" || true; fi
        ztg_log_error 'Existing mapping could not be stopped; unit files and state were not changed.'
        exit 1
      fi
    fi
    if ! install -m 0644 "$candidate_dir/$unit_base.socket" "$socket_path" || ! install -m 0644 "$candidate_dir/$unit_base.service" "$service_path"; then
      rm -f "$socket_path" "$service_path"
      if $exists; then
        printf '%s\n' "$old_socket" > "$socket_path"; printf '%s\n' "$old_service" > "$service_path"
        if [ "$old_firewall_mode" = ufw ]; then ztg_add_owned_ufw_rule "$name" "$old_listen_ip" "$old_listen_port" "$old_source_cidr" || true; fi
        systemctl daemon-reload >/dev/null 2>&1 || true; systemctl enable --now "$unit_base.socket" >/dev/null 2>&1 || true
      else
        systemctl daemon-reload >/dev/null 2>&1 || true
      fi
      ztg_log_error 'Unit installation failed; prior owned resources were restored.'
      exit 1
    fi
    firewall_mode=none; firewall_failed=false
    if ztg_add_owned_ufw_rule "$name" "$listen_ip" "$listen_port" "$source_cidr"; then firewall_mode=ufw; else rc=$?; [ "$rc" -eq 2 ] || firewall_failed=true; fi
    if $firewall_failed || ! systemctl daemon-reload || ! systemctl enable --now "$unit_base.socket"; then
      systemctl disable --now "$unit_base.socket" >/dev/null 2>&1 || true
      ztg_remove_owned_ufw_rule "$(ztg_publish_marker "$name")" || true
      if $exists; then
        printf '%s\n' "$old_socket" > "$socket_path"; printf '%s\n' "$old_service" > "$service_path"; ztg_atomic_write "$state_path" "$old_state" 0600
        if [ "$old_firewall_mode" = ufw ]; then ztg_add_owned_ufw_rule "$name" "$old_listen_ip" "$old_listen_port" "$old_source_cidr" || true; fi
        systemctl daemon-reload >/dev/null 2>&1 || true; systemctl enable --now "$unit_base.socket" >/dev/null 2>&1 || true
      else rm -f "$socket_path" "$service_path"; systemctl daemon-reload >/dev/null 2>&1 || true; fi
      ztg_log_error 'Mapping activation failed; prior owned resources were restored.'
      exit 1
    fi
    if $exists; then generation=$((generation + 1)); else generation=1; fi
    if ! ztg_write_publish_state "$state_path" "$name" "$listen_ip" "$listen_port" "$target_ip" "$target_port" "$source_cidr" "$generation" "$firewall_mode"; then
      systemctl disable --now "$unit_base.socket" >/dev/null 2>&1 || true
      ztg_remove_owned_ufw_rule "$(ztg_publish_marker "$name")" || true
      if $exists; then
        printf '%s\n' "$old_socket" > "$socket_path"; printf '%s\n' "$old_service" > "$service_path"; ztg_atomic_write "$state_path" "$old_state" 0600
        if [ "$old_firewall_mode" = ufw ]; then ztg_add_owned_ufw_rule "$name" "$old_listen_ip" "$old_listen_port" "$old_source_cidr" || true; fi
        systemctl daemon-reload >/dev/null 2>&1 || true; systemctl enable --now "$unit_base.socket" >/dev/null 2>&1 || true
      else
        rm -f "$socket_path" "$service_path"; systemctl daemon-reload >/dev/null 2>&1 || true
      fi
      ztg_log_error 'State write failed; prior owned resources were restored.'; exit 1
    fi
    ztg_log_info "Mapping enabled: ${listen_ip}:${listen_port} -> ${target_ip}:${target_port}"
    ztg_log_warn 'This command cannot open a cloud-provider security group; verify that layer separately.'
    ;;
  status|test)
    load_state "$state_path"
    ztg_log_info "Mapping $name: ${listen_ip}:${listen_port} -> ${target_ip}:${target_port}; source=${source_cidr:-any}; firewall=$firewall_mode"
    ztg_is_owned_publish_unit "$socket_path" "$name" && ztg_is_owned_publish_unit "$service_path" "$name" || { ztg_log_error 'Owned unit files are missing or changed.'; exit 1; }
    systemctl is-enabled "$unit_base.socket"; systemctl is-active "$unit_base.socket"
    if command -v timeout >/dev/null; then timeout 3 bash -c "</dev/tcp/$target_ip/$target_port" || { ztg_log_error 'ZeroTier target TCP check failed.'; exit 1; }; fi
    if [ "$action" = test ]; then
      command -v timeout >/dev/null || { ztg_log_error 'timeout is required for forwarding checks.'; exit 1; }
      local_check_ip="$listen_ip"; [ "$local_check_ip" = 0.0.0.0 ] && local_check_ip=127.0.0.1
      timeout 3 bash -c "</dev/tcp/$local_check_ip/$listen_port" || { ztg_log_error 'Local forwarding check failed.'; exit 1; }
      ztg_log_info 'Local target and forwarding layers passed. Test the public IP from an external network; a failure there indicates host/cloud/NAT routing.'
    fi
    ;;
  remove)
    load_state "$state_path"
    ztg_log_info "Plan: stop/remove only $unit_base and its marked UFW rule. Other mappings and relay units remain."
    if [ "$apply" != true ]; then ztg_log_warn 'Preview only. Re-run with --apply.'; exit 0; fi
    ztg_require_root
    ztg_is_owned_publish_unit "$socket_path" "$name" && ztg_is_owned_publish_unit "$service_path" "$name" || { ztg_log_error 'Unit ownership check failed.'; exit 1; }
    if [ "$firewall_mode" = ufw ]; then ztg_assert_owned_ufw_rule "$(ztg_publish_marker "$name")" || exit 1; fi
    rollback_dir="$(mktemp -d)"
    cp -a "$socket_path" "$rollback_dir/socket"
    cp -a "$service_path" "$rollback_dir/service"
    cp -a "$state_path" "$rollback_dir/state"
    trap 'rm -rf "$rollback_dir"; ztg_release_management_lock' EXIT
    restore_removed_mapping() {
      cp -a "$rollback_dir/socket" "$socket_path"
      cp -a "$rollback_dir/service" "$service_path"
      cp -a "$rollback_dir/state" "$state_path"
      if [ "$firewall_mode" = ufw ]; then
        ztg_add_owned_ufw_rule "$name" "$listen_ip" "$listen_port" "$source_cidr" || ztg_log_error 'The prior marked UFW rule could not be fully restored.'
      fi
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl enable --now "$unit_base.socket" >/dev/null 2>&1 || true
    }
    systemctl disable --now "$unit_base.socket" >/dev/null 2>&1 || { ztg_log_error 'Mapping socket could not be stopped; nothing was deleted.'; exit 1; }
    systemctl stop "$unit_base.service" >/dev/null 2>&1 || true
    if ! ztg_remove_owned_ufw_rule "$(ztg_publish_marker "$name")"; then
      ztg_remove_owned_ufw_rule "$(ztg_publish_marker "$name")" || true
      if [ "$firewall_mode" = ufw ]; then ztg_add_owned_ufw_rule "$name" "$listen_ip" "$listen_port" "$source_cidr" || ztg_log_error 'The prior marked UFW rule also could not be fully restored.'; fi
      systemctl enable --now "$unit_base.socket" >/dev/null 2>&1 || true
      ztg_log_error 'Marked UFW rule could not be removed; the mapping was restarted and files were kept.'
      exit 1
    fi
    if ! rm -f "$socket_path" "$service_path"; then
      restore_removed_mapping
      ztg_log_error 'Unit removal failed; project files, state, firewall, and service were restored.'
      exit 1
    fi
    if ! systemctl daemon-reload; then
      restore_removed_mapping
      ztg_log_error 'systemd reload failed; project files, state, firewall, and service were restored.'
      exit 1
    fi
    if ! rm -f "$state_path"; then
      restore_removed_mapping
      ztg_log_error 'State removal failed; project files, state, firewall, and service were restored.'
      exit 1
    fi
    ztg_log_info "Mapping removed: $name"
    ;;
esac
