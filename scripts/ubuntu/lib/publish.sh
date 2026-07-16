#!/usr/bin/env bash

ZTG_PUBLISH_MAX_MAPPINGS=64

ztg_validate_publish_name() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$ ]]
}

ztg_publish_state_path() {
  printf '%s/publish-ip-%s.json' "$(ztg_state_root)" "$1"
}

ztg_publish_unit_base() {
  printf 'zerotier-gateway-publish-%s' "$1"
}

ztg_validate_listen_address() {
  local value="${1:-}"
  [ "$value" = '0.0.0.0' ] || ztg_validate_ipv4_cidr "$value"
  [[ "$value" != */* ]]
}

ztg_publish_marker() {
  printf 'zerotier-gateway-publish-%s' "$1"
}

ztg_count_publish_states() {
  local count=0 file
  for file in "$(ztg_state_root)"/publish-ip-*.json; do [ -f "$file" ] && count=$((count + 1)); done
  printf '%s' "$count"
}

ztg_render_publish_socket() {
  local name="$1" listen_ip="$2" listen_port="$3"
  local template content marker
  template="$(<"$ZTG_ROOT/templates/systemd/zerotier-gateway-publish.socket.tmpl")"
  marker="$(ztg_publish_marker "$name")"
  content="${template//\{\{PUBLISH_MARKER\}\}/$marker}"
  content="${content//\{\{PUBLISH_NAME\}\}/$name}"
  content="${content//\{\{PUBLISH_LISTEN\}\}/${listen_ip}:${listen_port}}"
  printf '%s\n' "$content"
}

ztg_render_publish_service() {
  local name="$1" target_ip="$2" target_port="$3" socket_proxyd="$4"
  local template content marker unit
  template="$(<"$ZTG_ROOT/templates/systemd/zerotier-gateway-publish.service.tmpl")"
  marker="$(ztg_publish_marker "$name")"
  unit="$(ztg_publish_unit_base "$name").socket"
  content="${template//\{\{PUBLISH_MARKER\}\}/$marker}"
  content="${content//\{\{PUBLISH_NAME\}\}/$name}"
  content="${content//\{\{PUBLISH_SOCKET_UNIT\}\}/$unit}"
  content="${content//\{\{SOCKET_PROXYD_PATH\}\}/$socket_proxyd}"
  content="${content//\{\{PUBLISH_TARGET\}\}/${target_ip}:${target_port}}"
  printf '%s\n' "$content"
}

ztg_is_owned_publish_unit() {
  local path="$1" name="$2"
  [ -f "$path" ] && grep -Fqx "# Managed-By: $(ztg_publish_marker "$name")" "$path"
}

ztg_write_publish_state() {
  local path="$1" name="$2" listen_ip="$3" listen_port="$4" target_ip="$5" target_port="$6" source_cidr="$7" generation="$8"
  local firewall_mode="$9" json
  json=$(cat <<JSON
{
  "schemaVersion": ${ZTG_STATE_SCHEMA_VERSION},
  "objectVersion": 1,
  "owner": "${ZTG_STATE_OWNER}",
  "objectType": "publish-ip",
  "objectName": "$(ztg_json_escape "$name")",
  "enabled": true,
  "lastAppliedVersion": "$(ztg_json_escape "$(ztg_project_version)")",
  "generation": ${generation},
  "listenIp": "$(ztg_json_escape "$listen_ip")",
  "listenPort": "$(ztg_json_escape "$listen_port")",
  "targetIp": "$(ztg_json_escape "$target_ip")",
  "targetPort": "$(ztg_json_escape "$target_port")",
  "sourceCidr": "$(ztg_json_escape "$source_cidr")",
  "firewallMode": "$(ztg_json_escape "$firewall_mode")",
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
)
  ztg_atomic_write "$path" "$json" 0600
}

ztg_socket_proxyd_path() {
  local candidate
  for candidate in "$(command -v systemd-socket-proxyd 2>/dev/null || true)" /usr/lib/systemd/systemd-socket-proxyd /lib/systemd/systemd-socket-proxyd; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}

ztg_publish_port_occupied() {
  local listen_ip="$1" listen_port="$2"
  command -v ss >/dev/null 2>&1 || return 1
  ss -H -ltn "sport = :$listen_port" 2>/dev/null | awk -v ip="$listen_ip" '
    { local_addr=$4; sub(/:[^:]*$/, "", local_addr); gsub(/^\[|\]$/, "", local_addr); if (ip=="0.0.0.0" || local_addr==ip || local_addr=="0.0.0.0" || local_addr=="*") found=1 }
    END { exit(found ? 0 : 1) }
  '
}

ztg_ufw_rule_numbers() {
  local marker="$1"
  LC_ALL=C ufw status numbered 2>/dev/null | awk -v marker="$marker" '
    {
      position=index($0, marker)
      boundary=substr($0, position + length(marker), 1)
      if (position && (boundary == "" || boundary !~ /[A-Za-z0-9._-]/) && match($0, /\[[[:space:]]*[0-9]+\]/)) {
        number=substr($0,RSTART+1,RLENGTH-2)
        gsub(/[[:space:]]/,"",number)
        print number
      }
    }
  '
}

ztg_ufw_active() {
  command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status 2>/dev/null | grep -Fqx 'Status: active'
}

ztg_assert_owned_ufw_rule() {
  local marker="$1"
  ztg_ufw_active || { ztg_log_error "UFW is unavailable or inactive, so owned rule $marker cannot be verified."; return 1; }
  ztg_ufw_rule_numbers "$marker" | grep -q . || { ztg_log_error "Owned UFW rule is missing: $marker"; return 1; }
}

ztg_remove_owned_ufw_rule() {
  local marker="$1" numbers number
  command -v ufw >/dev/null 2>&1 || return 0
  numbers="$(ztg_ufw_rule_numbers "$marker")"
  [ -n "$numbers" ] || return 0
  while IFS= read -r number; do
    [ -n "$number" ] || continue
    ufw --force delete "$number" >/dev/null || return 1
  done < <(printf '%s\n' "$numbers" | sort -rn)
}

ztg_add_owned_ufw_rule() {
  local name="$1" listen_ip="$2" listen_port="$3" source_cidr="$4" marker destination
  command -v ufw >/dev/null 2>&1 || { ztg_log_warn 'ufw was not found; host and cloud firewall access must be opened separately.'; return 2; }
  ztg_ufw_active || { ztg_log_warn 'ufw is inactive; no dormant rule was added. Open the host/cloud firewall separately if needed.'; return 2; }
  marker="$(ztg_publish_marker "$name")"
  if ztg_ufw_rule_numbers "$marker" | grep -q .; then ztg_log_error "UFW marker already exists: $marker"; return 1; fi
  if [ "$listen_ip" = '0.0.0.0' ]; then destination=any; else destination="$listen_ip"; fi
  if [ -n "$source_cidr" ]; then
    ufw allow from "$source_cidr" to "$destination" port "$listen_port" proto tcp comment "$marker" >/dev/null
  else
    ufw allow from any to "$destination" port "$listen_port" proto tcp comment "$marker" >/dev/null
  fi
  ztg_ufw_rule_numbers "$marker" | grep -q . || { ztg_log_error "UFW did not materialize the project marker: $marker"; return 1; }
}
