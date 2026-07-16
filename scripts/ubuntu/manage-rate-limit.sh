#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/rate-limit.sh"

usage() {
  cat <<'HELP'
Manage per-client proxy rate limits without editing configuration files.

Usage:
  manage-rate-limit.sh add|update [options] [--apply]
  manage-rate-limit.sh list|status|test [--name NAME]
  manage-rate-limit.sh disable|remove --name NAME [--apply]
  manage-rate-limit.sh restore --apply

Options:
  --name NAME             Rule name.
  --client IP[/CIDR]      ZeroTier client IP, or public source CIDR.
  --upload RATE           Client upload ceiling, such as 5mbit.
  --download RATE         Client download ceiling, such as 20mbit.
  --proxy-port PORT       Project proxy port. Default: 10808.
  --interface NAME        Interface; auto-detected from the client route when omitted.
  --source-mode MODE      zerotier (default) or public.
  --zerotier-subnet CIDR  Validation subnet. Default: 10.246.77.0/24.
  --apply                 Apply the displayed plan. Without it, no state is changed.
HELP
}

[ "$#" -gt 0 ] || { usage; exit 2; }
action="$1"; shift
case "$action" in add|update|list|status|test|disable|remove|restore) ;; *) usage; exit 2 ;; esac

name="" client="" upload="" download="" proxy_port="" interface="" source_mode="" zerotier_subnet="10.246.77.0/24" apply=false
has_client=false; has_upload=false; has_download=false; has_proxy_port=false; has_interface=false; has_source_mode=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --client) client="${2:-}"; has_client=true; shift 2 ;;
    --upload) upload="${2:-}"; has_upload=true; shift 2 ;;
    --download) download="${2:-}"; has_download=true; shift 2 ;;
    --proxy-port) proxy_port="${2:-}"; has_proxy_port=true; shift 2 ;;
    --interface) interface="${2:-}"; has_interface=true; shift 2 ;;
    --source-mode) source_mode="${2:-}"; has_source_mode=true; shift 2 ;;
    --zerotier-subnet) zerotier_subnet="${2:-}"; shift 2 ;;
    --apply) apply=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ztg_log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

state_root="$(ztg_state_root)"
unit_dir="${ZTG_SYSTEMD_DIR:-/etc/systemd/system}"
unit_path="$unit_dir/zerotier-gateway-rate-limit.service"

require_name() {
  if [ -z "$name" ] && [ -t 0 ]; then read -r -p 'Rule name: ' name; fi
  ztg_validate_rate_limit_name "$name" || { ztg_log_error 'A valid --name is required.'; exit 2; }
}

load_state() {
  local path="$1"
  [ -f "$path" ] || { ztg_log_error "Rate-limit rule not found: $name"; exit 1; }
  ztg_validate_state_identity "$path" rate-limit "$name" || exit 1
  interface="$(ztg_read_json_scalar "$path" interface)"
  client="$(ztg_read_json_scalar "$path" client)"
  proxy_port="$(ztg_read_json_scalar "$path" proxyPort)"
  upload="$(ztg_read_json_scalar "$path" uploadRate)"
  download="$(ztg_read_json_scalar "$path" downloadRate)"
  source_mode="$(ztg_read_json_scalar "$path" sourceMode)"
  slot="$(ztg_read_json_scalar "$path" slot)"
  enabled="$(ztg_json_boolean "$path" enabled)"
  generation="$(sed -nE 's/^[[:space:]]*"generation"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$path" | head -n 1)"
}

install_restore_unit() {
  local manager target temporary content
  manager="$(cd "$SCRIPT_DIR" && pwd)/manage-rate-limit.sh"
  target="$unit_path"
  content="$(<"$ZTG_ROOT/templates/systemd/zerotier-gateway-rate-limit.service.tmpl")"
  content="${content//\{\{RATE_LIMIT_MANAGER_PATH\}\}/$manager}"
  install -d -m 0755 "$(dirname "$target")" || return 1
  temporary="$(mktemp "$(dirname "$target")/.ztg-rate-unit.XXXXXX")" || return 1
  printf '%s\n' "$content" > "$temporary" || return 1
  chmod 0644 "$temporary" || return 1
  mv -f "$temporary" "$target" || return 1
  systemctl daemon-reload || return 1
  systemctl enable zerotier-gateway-rate-limit.service >/dev/null || return 1
}

if [ "$action" = list ]; then
  found=false
  for file in "$state_root"/rate-limit-*.json; do
    [ -f "$file" ] || continue; found=true
    state_name="$(basename "$file")"; state_name="${state_name#rate-limit-}"; state_name="${state_name%.json}"
    ztg_validate_state_identity "$file" rate-limit "$state_name" || exit 1
    printf '%-20s client=%-18s upload=%-10s download=%-10s enabled=%s\n' \
      "$(ztg_read_json_scalar "$file" objectName)" "$(ztg_read_json_scalar "$file" client)" \
      "$(ztg_read_json_scalar "$file" uploadRate)" "$(ztg_read_json_scalar "$file" downloadRate)" "$(ztg_json_boolean "$file" enabled)"
  done
  $found || ztg_log_warn 'No rate-limit rules are configured.'
  exit 0
fi

if [ "$action" = restore ]; then
  [ "$apply" = true ] || { ztg_log_error 'restore requires --apply.'; exit 2; }
  ztg_require_root
  ztg_acquire_management_lock
  trap 'ztg_release_management_lock' EXIT
  command -v tc >/dev/null || { ztg_log_error 'tc is required (package: iproute2).'; exit 1; }
  for file in "$state_root"/rate-limit-*.json; do
    [ -f "$file" ] || continue
    state_name="$(basename "$file")"; state_name="${state_name#rate-limit-}"; state_name="${state_name%.json}"
    ztg_validate_state_identity "$file" rate-limit "$state_name" || exit 1
    [ "$(ztg_json_boolean "$file" enabled)" = true ] || continue
    name="$state_name"; load_state "$file"
    ztg_assert_rate_limit_slot_available "$interface" "$slot" true
    if ! ztg_remove_rate_limit_filters "$interface" "$slot"; then
      ztg_remove_rate_limit_filters "$interface" "$slot" || true
      ztg_apply_rate_limit_filters "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" || true
      ztg_log_error "Could not clear all existing filters before restoring rule: $name"
      exit 1
    fi
    ztg_apply_rate_limit_filters "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot"
    ztg_log_info "Restored rate-limit rule: $name"
  done
  exit 0
fi

require_name
state_path="$(ztg_rate_limit_state_path "$name")"
case "$action" in
  add|update|disable|remove)
    if [ "$apply" = true ]; then
      ztg_require_root
      ztg_acquire_management_lock
      trap 'ztg_release_management_lock' EXIT
    fi
    ;;
esac

case "$action" in
  add|update)
    exists=false
    requested_client="$client"; requested_upload="$upload"; requested_download="$download"; requested_port="$proxy_port"; requested_interface="$interface"; requested_source_mode="$source_mode"
    if [ -f "$state_path" ]; then
      exists=true; load_state "$state_path"
      old_interface="$interface"; old_client="$client"; old_port="$proxy_port"; old_upload="$upload"; old_download="$download"
      old_enabled="$enabled"
      $has_client && client="$requested_client"
      $has_upload && upload="$requested_upload"
      $has_download && download="$requested_download"
      $has_proxy_port && proxy_port="$requested_port"
      $has_interface && interface="$requested_interface"
      $has_source_mode && source_mode="$requested_source_mode"
    else
      client="$requested_client"; upload="$requested_upload"; download="$requested_download"
      proxy_port="${requested_port:-10808}"; interface="$requested_interface"; source_mode="${requested_source_mode:-zerotier}"
    fi
    if [ "$action" = add ] && $exists; then ztg_log_error "Rule already exists: $name"; exit 1; fi
    if [ "$action" = update ] && ! $exists; then ztg_log_error "Rule not found: $name"; exit 1; fi
    if [ -t 0 ]; then
      [ -n "$client" ] || read -r -p 'Client IP or CIDR: ' client
      [ -n "$upload" ] || read -r -p 'Upload limit (for example 5mbit): ' upload
      [ -n "$download" ] || read -r -p 'Download limit (for example 20mbit): ' download
    fi
    ztg_validate_ipv4_cidr "$client" || { ztg_log_error 'A valid IPv4 client or CIDR is required.'; exit 2; }
    if [ "$source_mode" = zerotier ]; then
      ztg_ipv4_in_cidr "${client%%/*}" "$zerotier_subnet" || { ztg_log_error "$client is outside ZeroTier subnet $zerotier_subnet."; exit 1; }
    elif [ "$source_mode" != public ]; then ztg_log_error '--source-mode must be zerotier or public.'; exit 2; fi
    upload="$(ztg_normalize_rate "$upload")" || { ztg_log_error 'Invalid upload rate; use kbit, mbit, or gbit.'; exit 2; }
    download="$(ztg_normalize_rate "$download")" || { ztg_log_error 'Invalid download rate; use kbit, mbit, or gbit.'; exit 2; }
    ztg_validate_proxy_port "$proxy_port" || { ztg_log_error 'Invalid proxy port.'; exit 2; }
    if [ -z "$interface" ]; then interface="$(ztg_detect_rate_limit_interface "$client")"; fi
    ztg_validate_interface_name "$interface" || { ztg_log_error 'Could not determine a valid interface; pass --interface.'; exit 1; }
    if ! $exists; then slot="$(ztg_allocate_rate_limit_slot)"; generation=1; enabled=true; else generation=$((generation + 1)); fi
    ztg_log_info "Plan: $action $name on $interface; client=$client; proxy-port=$proxy_port; upload=$upload; download=$download"
    ztg_rate_limit_print_commands "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" | sed 's/^/[PLAN] /'
    if [ "$apply" != true ]; then ztg_log_warn 'Preview only. Re-run with --apply to change tc and save state.'; exit 0; fi
    ztg_require_root
    command -v tc >/dev/null || { ztg_log_error 'tc is required (package: iproute2).'; exit 1; }
    old_state_exists=false; old_state_content=''; old_unit_exists=false; old_unit_content=''
    if [ -f "$state_path" ]; then old_state_exists=true; old_state_content="$(<"$state_path")"; fi
    if [ -f "$unit_path" ]; then old_unit_exists=true; old_unit_content="$(<"$unit_path")"; fi
    if $exists; then
      ztg_assert_rate_limit_slot_available "$old_interface" "$slot" true
      if [ "$interface" != "$old_interface" ]; then ztg_assert_rate_limit_slot_available "$interface" "$slot" false; fi
      if ! ztg_remove_rate_limit_filters "$old_interface" "$slot"; then
        ztg_remove_rate_limit_filters "$old_interface" "$slot" || true
        if [ "$old_enabled" = true ]; then ztg_apply_rate_limit_filters "$old_interface" "$old_client" "$old_port" "$old_upload" "$old_download" "$slot" || true; fi
        ztg_log_error 'Existing project filters could not be replaced; saved state was not changed.'
        exit 1
      fi
    else
      ztg_assert_rate_limit_slot_available "$interface" "$slot" false
    fi
    if ! ztg_apply_rate_limit_filters "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot"; then
      if $exists && [ "$old_enabled" = true ]; then
        ztg_log_warn 'New filters failed; restoring the previous rule.'
        ztg_apply_rate_limit_filters "$old_interface" "$old_client" "$old_port" "$old_upload" "$old_download" "$slot" || ztg_log_error 'Previous filters could not be restored; state was kept for the restore command.'
      fi
      ztg_log_error 'Apply failed; saved state was not changed.'
      exit 1
    fi
    if ! ztg_write_rate_limit_state "$state_path" "$name" "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" "$source_mode" true "$generation"; then
      ztg_remove_rate_limit_filters "$interface" "$slot" || true
      if $exists && [ "$old_enabled" = true ]; then ztg_apply_rate_limit_filters "$old_interface" "$old_client" "$old_port" "$old_upload" "$old_download" "$slot" || true; fi
      ztg_log_error 'State write failed; kernel filters were rolled back.'
      exit 1
    fi
    if ! install_restore_unit; then
      ztg_remove_rate_limit_filters "$interface" "$slot" || true
      if $exists && [ "$old_enabled" = true ]; then ztg_apply_rate_limit_filters "$old_interface" "$old_client" "$old_port" "$old_upload" "$old_download" "$slot" || true; fi
      if $old_state_exists; then ztg_atomic_write "$state_path" "$old_state_content" 0600; else rm -f "$state_path"; fi
      if $old_unit_exists; then
        rollback_unit="$(mktemp "$(dirname "$unit_path")/.ztg-rate-rollback.XXXXXX")"
        printf '%s\n' "$old_unit_content" > "$rollback_unit"
        chmod 0644 "$rollback_unit"
        mv -f "$rollback_unit" "$unit_path"
      else
        rm -f "$unit_path"
        systemctl disable zerotier-gateway-rate-limit.service >/dev/null 2>&1 || true
      fi
      systemctl daemon-reload >/dev/null 2>&1 || true
      ztg_log_error 'Restore-unit installation failed; state and kernel filters were rolled back.'
      exit 1
    fi
    ztg_log_info "Rate limit enabled: $name"
    ;;
  status|test)
    load_state "$state_path"
    ztg_log_info "Rule $name: enabled=$enabled interface=$interface client=$client proxy-port=$proxy_port upload=$upload download=$download"
    if [ "$enabled" = true ] && command -v tc >/dev/null; then
      missing=0
      for offset in 0 1 2 3; do if [ "$offset" -lt 2 ]; then hook=ingress; else hook=egress; fi; ztg_rate_limit_filter_exists "$interface" "$hook" "$slot" "$offset" || missing=$((missing + 1)); done
      [ "$missing" -eq 0 ] || { ztg_log_error "$missing of 4 project filters are missing."; exit 1; }
      tc -s filter show dev "$interface" ingress pref "$(ztg_rate_limit_pref "$slot" 0)"
      tc -s filter show dev "$interface" egress pref "$(ztg_rate_limit_pref "$slot" 2)"
      ztg_log_info 'Kernel filters are present. For acceptance, compare sustained proxy speed for this client with an unlimited client, RDP, and relay.'
    elif [ "$enabled" = true ]; then ztg_log_error 'tc is unavailable.'; exit 1; fi
    ;;
  disable|remove)
    load_state "$state_path"
    ztg_log_info "Plan: remove exactly four owned filters for $name; clsact and all third-party filters remain."
    if [ "$apply" != true ]; then ztg_log_warn 'Preview only. Re-run with --apply.'; exit 0; fi
    ztg_require_root
    command -v tc >/dev/null || { ztg_log_error 'tc is required (package: iproute2).'; exit 1; }
    old_state_content="$(<"$state_path")"
    remaining_rules=0
    if [ "$action" = remove ]; then
      for remaining_state in "$state_root"/rate-limit-*.json; do [ -f "$remaining_state" ] && [ "$remaining_state" != "$state_path" ] && remaining_rules=$((remaining_rules + 1)); done
      if [ "$remaining_rules" -eq 0 ] && [ -f "$unit_path" ]; then
        grep -Fqx '# Managed-By: zerotier-gateway-rate-limit' "$unit_path" || { ztg_log_error "Restore unit ownership mismatch: $unit_path"; exit 1; }
      fi
    fi
    ztg_assert_rate_limit_slot_available "$interface" "$slot" true
    if ! ztg_remove_rate_limit_filters "$interface" "$slot"; then
      ztg_remove_rate_limit_filters "$interface" "$slot" || true
      if [ "$enabled" = true ]; then ztg_apply_rate_limit_filters "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" || true; fi
      ztg_log_error 'Owned filters could not be removed cleanly; saved state was not changed.'
      exit 1
    fi
    if [ "$action" = disable ]; then
      if ! ztg_write_rate_limit_state "$state_path" "$name" "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" "$source_mode" false "$((generation + 1))"; then
        if [ "$enabled" = true ]; then ztg_apply_rate_limit_filters "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" || true; fi
        ztg_log_error 'State write failed; the previous kernel filters were restored.'
        exit 1
      fi
      ztg_log_info 'Rule disabled; saved settings can be restored by Update --apply.'
    else
      if ! rm -f "$state_path"; then
        if [ "$enabled" = true ]; then ztg_apply_rate_limit_filters "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" || true; fi
        ztg_log_error 'State removal failed; the previous kernel filters were restored.'
        exit 1
      fi
      if [ "$remaining_rules" -eq 0 ] && [ -f "$unit_path" ]; then
        if ! systemctl disable --now zerotier-gateway-rate-limit.service >/dev/null 2>&1; then
          ztg_atomic_write "$state_path" "$old_state_content" 0600
          if [ "$enabled" = true ]; then ztg_apply_rate_limit_filters "$interface" "$client" "$proxy_port" "$upload" "$download" "$slot" || true; fi
          ztg_log_error 'Restore service could not be disabled; state and kernel filters were restored.'
          exit 1
        fi
        rm -f "$unit_path"
        systemctl daemon-reload
      fi
      ztg_log_info 'Rule removed. clsact was intentionally retained so third-party ownership is never guessed.'
    fi
    ;;
esac
