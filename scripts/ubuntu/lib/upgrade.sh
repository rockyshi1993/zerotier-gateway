#!/usr/bin/env bash

ztg_system_path() {
  local system_root="${1:-/}"
  local absolute="$2"
  if [ "$system_root" = "/" ]; then
    printf '%s' "$absolute"
  else
    printf '%s%s' "${system_root%/}" "$absolute"
  fi
}

ztg_has_unit() {
  local system_root="$1"
  local unit_name="$2"
  local unit_path
  unit_path="$(ztg_system_path "$system_root" "/etc/systemd/system/$unit_name")"
  if [ -f "$unit_path" ]; then
    return 0
  fi
  if [ "$system_root" = "/" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl cat "$unit_name" >/dev/null 2>&1
    return $?
  fi
  return 1
}

ztg_detect_installation() {
  local system_root="${1:-/}"
  local project_root="${2:-$ZTG_ROOT}"
  local historical=false modular=false

  if ztg_has_unit "$system_root" "zerotier-gateway.service" \
    || [ -f "$(ztg_system_path "$system_root" "/usr/local/bin/zerotier-gateway-startup.sh")" ] \
    || [ -f "$(ztg_system_path "$system_root" "/etc/zerotier-gateway.conf")" ]; then
    historical=true
  fi

  if ztg_has_unit "$system_root" "sing-box-zt-proxy.service" \
    || [ -f "$(ztg_system_path "$system_root" "/etc/zerotier-gateway/sing-box-server.json")" ]; then
    modular=true
  fi

  if [ "$historical" = "true" ] && [ "$modular" = "true" ]; then
    printf '%s' "unknown-mixed"
  elif [ "$historical" = "true" ]; then
    printf '%s' "historical-gateway"
  elif [ "$modular" = "true" ]; then
    printf '%s' "modular-proxy"
  elif [ -d "$project_root/.git" ] || [ -f "$project_root/VERSION" ]; then
    printf '%s' "source-only"
  else
    printf '%s' "unknown"
  fi
}

ztg_command_output_hash() {
  local output="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$output" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$output" | shasum -a 256 | awk '{print $1}'
  fi
}

ztg_service_fact() {
  local unit="$1"
  if ! command -v systemctl >/dev/null 2>&1; then
    printf '%s' "unavailable"
    return 0
  fi
  systemctl show "$unit" --no-pager \
    --property=LoadState,ActiveState,SubState,MainPID,ExecMainStartTimestampMonotonic 2>/dev/null \
    | sort || true
}

ztg_capture_runtime_snapshot() {
  local system_root="${1:-/}"
  local output=""
  local path label unit

  if [ "$system_root" = "/" ]; then
    for unit in zerotier-one.service zerotier-gateway.service sing-box-zt-proxy.service; do
      output+="service:$unit=$(ztg_command_output_hash "$(ztg_service_fact "$unit")")"$'\n'
    done
    if command -v systemctl >/dev/null 2>&1; then
      output+="relay-units=$(ztg_command_output_hash "$(systemctl list-unit-files 'zerotier-gateway-relay-*' --no-legend --no-pager 2>/dev/null | sort || true)")"$'\n'
    else
      output+="relay-units=unavailable"$'\n'
    fi
  else
    output+="service:zerotier-one.service=fixture"$'\n'
    output+="service:zerotier-gateway.service=fixture"$'\n'
    output+="service:sing-box-zt-proxy.service=fixture"$'\n'
    output+="relay-units=fixture"$'\n'
  fi

  while IFS='|' read -r label path; do
    output+="file:$label=$(ztg_sha256_file "$(ztg_system_path "$system_root" "$path")")"$'\n'
  done <<'FILES'
legacy-conf|/etc/zerotier-gateway.conf
legacy-startup|/usr/local/bin/zerotier-gateway-startup.sh
proxy-config|/etc/zerotier-gateway/sing-box-server.json
legacy-unit|/etc/systemd/system/zerotier-gateway.service
proxy-unit|/etc/systemd/system/sing-box-zt-proxy.service
FILES

  if [ "$system_root" = "/" ]; then
    if command -v ss >/dev/null 2>&1; then
      output+="listeners=$(ztg_command_output_hash "$(ss -H -lntup 2>/dev/null | sed -E 's/users:\(.*\)$//' | sort || true)")"$'\n'
    else
      output+="listeners=unavailable"$'\n'
    fi
    if command -v ufw >/dev/null 2>&1; then
      output+="ufw=$(ztg_command_output_hash "$(ufw status numbered 2>/dev/null || true)")"$'\n'
    else
      output+="ufw=unavailable"$'\n'
    fi
    if command -v iptables-save >/dev/null 2>&1; then
      output+="iptables=$(ztg_command_output_hash "$(iptables-save 2>/dev/null || true)")"$'\n'
    else
      output+="iptables=unavailable"$'\n'
    fi
    if command -v tc >/dev/null 2>&1; then
      output+="tc=$(ztg_command_output_hash "$(tc qdisc show 2>/dev/null; tc filter show 2>/dev/null || true)")"$'\n'
    else
      output+="tc=unavailable"$'\n'
    fi
  else
    output+="listeners=fixture"$'\n'"ufw=fixture"$'\n'"iptables=fixture"$'\n'"tc=fixture"$'\n'
  fi
  printf '%s' "$output"
}

ztg_upgrade_backup_paths() {
  cat <<'PATHS'
/etc/zerotier-gateway.conf
/usr/local/bin/zerotier-gateway-startup.sh
/etc/zerotier-gateway
/etc/systemd/system/zerotier-gateway.service
/etc/systemd/system/sing-box-zt-proxy.service
PATHS
}

ztg_create_upgrade_backup() {
  local backup_dir="$1"
  local system_root="${2:-/}"
  local project_root="${3:-$ZTG_ROOT}"
  local absolute source destination
  install -d -m 0700 "$backup_dir/system" "$backup_dir/project" "$backup_dir/state"
  while IFS= read -r absolute; do
    source="$(ztg_system_path "$system_root" "$absolute")"
    [ -e "$source" ] || continue
    destination="$backup_dir/system${absolute}"
    install -d -m 0700 "$(dirname "$destination")"
    cp -a "$source" "$destination"
  done < <(ztg_upgrade_backup_paths)
  [ -f "$project_root/.env" ] && cp -a "$project_root/.env" "$backup_dir/project/.env"
  if [ -d "$(ztg_state_root)" ]; then
    cp -a "$(ztg_state_root)/." "$backup_dir/state/"
  fi
}

ztg_restore_management_state() {
  local backup_dir="$1"
  local state_root
  state_root="$(ztg_state_root)"
  rm -f "$state_root/installation.json"
  if [ -d "$backup_dir/state" ] && [ -n "$(find "$backup_dir/state" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    install -d -m 0750 "$state_root"
    cp -a "$backup_dir/state/." "$state_root/"
  fi
}

ztg_git_head() {
  git -C "$ZTG_ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf '%s' "source-archive"
}
