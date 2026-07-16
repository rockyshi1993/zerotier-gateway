#!/usr/bin/env bash

ZTG_RATE_LIMIT_PREF_BASE=42000
ZTG_RATE_LIMIT_MAX_RULES=100

ztg_validate_rate_limit_name() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
}

ztg_validate_interface_name() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,31}$ ]]
}

ztg_validate_ipv4_cidr() {
  local value="${1:-}" address prefix octet
  address="${value%%/*}"
  prefix="32"
  if [[ "$value" == */* ]]; then prefix="${value#*/}"; fi
  [[ "$prefix" =~ ^[0-9]+$ ]] && [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ] || return 1
  IFS='.' read -r -a octets <<< "$address"
  [ "${#octets[@]}" -eq 4 ] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] && [ "$octet" -ge 0 ] && [ "$octet" -le 255 ] || return 1
  done
}

ztg_ipv4_to_int() {
  local address="${1%%/*}" a b c d
  IFS='.' read -r a b c d <<< "$address"
  printf '%u' "$(( (10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d ))"
}

ztg_ipv4_in_cidr() {
  local address="$1" cidr="$2" prefix mask address_int network_int
  ztg_validate_ipv4_cidr "$address" || return 1
  ztg_validate_ipv4_cidr "$cidr" || return 1
  prefix="${cidr#*/}"
  if [ "$prefix" = "$cidr" ]; then prefix=32; fi
  address_int="$(ztg_ipv4_to_int "$address")"
  network_int="$(ztg_ipv4_to_int "$cidr")"
  if [ "$prefix" -eq 0 ]; then mask=0; else mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF )); fi
  [ "$((address_int & mask))" -eq "$((network_int & mask))" ]
}

ztg_normalize_rate() {
  local value
  value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  if ! [[ "$value" =~ ^[1-9][0-9]*(kbit|mbit|gbit)$ ]]; then
    return 1
  fi
  printf '%s' "$value"
}

ztg_validate_proxy_port() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

ztg_rate_limit_state_path() {
  printf '%s/rate-limit-%s.json' "$(ztg_state_root)" "$1"
}

ztg_rate_limit_slot_in_use() {
  local slot="$1" exclude="${2:-}" file existing expected_name
  for file in "$(ztg_state_root)"/rate-limit-*.json; do
    [ -f "$file" ] || continue
    [ "$file" = "$exclude" ] && continue
    expected_name="$(basename "$file")"; expected_name="${expected_name#rate-limit-}"; expected_name="${expected_name%.json}"
    ztg_validate_state_identity "$file" rate-limit "$expected_name" || return 2
    existing="$(ztg_read_json_scalar "$file" slot 2>/dev/null || true)"
    [ "$existing" = "$slot" ] && return 0
  done
  return 1
}

ztg_allocate_rate_limit_slot() {
  local exclude="${1:-}" slot result
  for ((slot=0; slot<ZTG_RATE_LIMIT_MAX_RULES; slot++)); do
    if ztg_rate_limit_slot_in_use "$slot" "$exclude"; then
      continue
    else
      result=$?
      [ "$result" -eq 1 ] || return "$result"
      printf '%s' "$slot"
      return 0
    fi
  done
  ztg_log_error "The first-release limit of ${ZTG_RATE_LIMIT_MAX_RULES} rate-limit rules has been reached."
  return 1
}

ztg_rate_limit_pref() {
  local slot="$1" offset="$2"
  printf '%s' "$((ZTG_RATE_LIMIT_PREF_BASE + slot * 4 + offset))"
}

ztg_rate_limit_handle() {
  local slot="$1" offset="$2"
  printf '0x%x' "$((0x5a000000 + slot * 16 + offset + 1))"
}

ztg_rate_limit_action_index() {
  local slot="$1" offset="$2"
  printf '%s' "$((52000 + slot * 4 + offset))"
}

ztg_rate_limit_filter_command() {
  local interface="$1" hook="$2" protocol="$3" client="$4" port_key="$5" port="$6" rate="$7" slot="$8" offset="$9"
  local pref handle action_index address_key
  pref="$(ztg_rate_limit_pref "$slot" "$offset")"
  handle="$(ztg_rate_limit_handle "$slot" "$offset")"
  action_index="$(ztg_rate_limit_action_index "$slot" "$offset")"
  if [ "$hook" = "ingress" ]; then address_key="src_ip"; else address_key="dst_ip"; fi
  printf 'tc filter add dev %q %q protocol ip pref %q handle %q flower ip_proto %q %q %q %q %q action police rate %q burst 256kb mtu 64kb conform-exceed drop index %q' \
    "$interface" "$hook" "$pref" "$handle" "$protocol" "$address_key" "$client" "$port_key" "$port" "$rate" "$action_index"
}

ztg_rate_limit_delete_command() {
  local interface="$1" hook="$2" slot="$3" offset="$4"
  printf 'tc filter del dev %q %q protocol ip pref %q handle %q flower' \
    "$interface" "$hook" "$(ztg_rate_limit_pref "$slot" "$offset")" "$(ztg_rate_limit_handle "$slot" "$offset")"
}

ztg_rate_limit_print_commands() {
  local interface="$1" client="$2" port="$3" upload="$4" download="$5" slot="$6"
  ztg_rate_limit_filter_command "$interface" ingress tcp "$client" dst_port "$port" "$upload" "$slot" 0; printf '\n'
  ztg_rate_limit_filter_command "$interface" ingress udp "$client" dst_port "$port" "$upload" "$slot" 1; printf '\n'
  ztg_rate_limit_filter_command "$interface" egress tcp "$client" src_port "$port" "$download" "$slot" 2; printf '\n'
  ztg_rate_limit_filter_command "$interface" egress udp "$client" src_port "$port" "$download" "$slot" 3; printf '\n'
}

ztg_rate_limit_filter_exists() {
  local interface="$1" hook="$2" slot="$3" offset="$4" output
  output="$(tc filter show dev "$interface" "$hook" pref "$(ztg_rate_limit_pref "$slot" "$offset")" 2>/dev/null || true)"
  [ -n "$output" ] && printf '%s' "$output" | grep -Fq "$(ztg_rate_limit_handle "$slot" "$offset")"
}

ztg_assert_rate_limit_slot_available() {
  local interface="$1" slot="$2" owned="${3:-false}" offset hook
  for offset in 0 1 2 3; do
    if [ "$offset" -lt 2 ]; then hook=ingress; else hook=egress; fi
    if tc filter show dev "$interface" "$hook" pref "$(ztg_rate_limit_pref "$slot" "$offset")" 2>/dev/null | grep -q .; then
      if [ "$owned" != "true" ] || ! ztg_rate_limit_filter_exists "$interface" "$hook" "$slot" "$offset"; then
        ztg_log_error "tc preference $(ztg_rate_limit_pref "$slot" "$offset") on $interface/$hook is not owned by this state object."
        return 1
      fi
    fi
  done
}

ztg_ensure_clsact() {
  local interface="$1"
  if tc qdisc show dev "$interface" 2>/dev/null | grep -Eq '(^| )clsact '; then return 0; fi
  tc qdisc add dev "$interface" clsact
}

ztg_remove_rate_limit_filters() {
  local interface="$1" slot="$2" offset hook command failed=false
  for offset in 0 1 2 3; do
    if [ "$offset" -lt 2 ]; then hook=ingress; else hook=egress; fi
    if ztg_rate_limit_filter_exists "$interface" "$hook" "$slot" "$offset"; then
      command="$(ztg_rate_limit_delete_command "$interface" "$hook" "$slot" "$offset")"
      eval "$command" || failed=true
    fi
  done
  ! $failed
}

ztg_apply_rate_limit_filters() {
  local interface="$1" client="$2" port="$3" upload="$4" download="$5" slot="$6" command applied=0
  ztg_ensure_clsact "$interface"
  while IFS= read -r command; do
    [ -n "$command" ] || continue
    if ! eval "$command"; then
      ztg_remove_rate_limit_filters "$interface" "$slot" || true
      ztg_log_error "Failed after applying $applied of 4 filters; this rule was rolled back."
      return 1
    fi
    applied=$((applied + 1))
  done < <(ztg_rate_limit_print_commands "$interface" "$client" "$port" "$upload" "$download" "$slot")
}

ztg_write_rate_limit_state() {
  local path="$1" name="$2" interface="$3" client="$4" port="$5" upload="$6" download="$7" slot="$8" source_mode="$9" enabled="${10}" generation="${11}"
  local json
  json=$(cat <<JSON
{
  "schemaVersion": ${ZTG_STATE_SCHEMA_VERSION},
  "objectVersion": 1,
  "owner": "${ZTG_STATE_OWNER}",
  "objectType": "rate-limit",
  "objectName": "$(ztg_json_escape "$name")",
  "enabled": ${enabled},
  "lastAppliedVersion": "$(ztg_json_escape "$(ztg_project_version)")",
  "generation": ${generation},
  "interface": "$(ztg_json_escape "$interface")",
  "client": "$(ztg_json_escape "$client")",
  "proxyPort": "$(ztg_json_escape "$port")",
  "uploadRate": "$(ztg_json_escape "$upload")",
  "downloadRate": "$(ztg_json_escape "$download")",
  "sourceMode": "$(ztg_json_escape "$source_mode")",
  "slot": "$(ztg_json_escape "$slot")",
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
)
  ztg_atomic_write "$path" "$json" 0600
}

ztg_json_boolean() {
  local path="$1" key="$2"
  sed -nE 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*(true|false).*/\1/p' "$path" | head -n 1
}

ztg_detect_rate_limit_interface() {
  local client="${1%%/*}"
  ip -4 route get "$client" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}
