#!/usr/bin/env bash

ZTG_EXIT_NODE_OBJECT_NAME="default"
ZTG_EXIT_NODE_MARKER="zerotier-gateway-exit-node"
ZTG_EXIT_NODE_NAT_COMMENT="ztg-exit-node-nat"
ZTG_EXIT_NODE_FORWARD_OUT_COMMENT="ztg-exit-node-forward-out"
ZTG_EXIT_NODE_FORWARD_IN_COMMENT="ztg-exit-node-forward-in"
ZTG_EXIT_NODE_UNIT_NAME="zerotier-gateway-exit-node.service"

ztg_exit_node_state_path() {
  printf '%s/exit-node.json' "$(ztg_state_root)"
}

ztg_exit_node_sysctl_path() {
  printf '%s/99-zerotier-gateway-exit-node.conf' "${ZTG_SYSCTL_DIR:-/etc/sysctl.d}"
}

ztg_exit_node_unit_path() {
  printf '%s/%s' "${ZTG_SYSTEMD_DIR:-/etc/systemd/system}" "$ZTG_EXIT_NODE_UNIT_NAME"
}

ztg_exit_node_validate_interface_name() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,31}$ ]]
}

ztg_exit_node_validate_ipv4_cidr() {
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

ztg_exit_node_validate_ipv4_address() {
  [[ "${1:-}" != */* ]] && ztg_exit_node_validate_ipv4_cidr "$1"
}

ztg_exit_node_sha256_text() {
  local text="${1:-}"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
  else
    ztg_log_error "sha256sum or shasum is required."
    return 1
  fi
}

ztg_exit_node_json_boolean() {
  local path="$1" key="$2"
  sed -nE 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*(true|false).*/\1/p' "$path" | head -n 1
}

ztg_exit_node_detect_zt_interface() {
  local ubuntu_zt_ip="$1"
  command -v ip >/dev/null 2>&1 || return 1
  ip -o -4 addr show 2>/dev/null | awk -v target="$ubuntu_zt_ip" '
    {
      split($4, parts, "/")
      if (parts[1] == target) {
        print $2
        exit
      }
    }
  '
}

ztg_exit_node_detect_wan_interface() {
  command -v ip >/dev/null 2>&1 || return 1
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

ztg_exit_node_read_ip_forward() {
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n net.ipv4.ip_forward 2>/dev/null
  elif [ -r /proc/sys/net/ipv4/ip_forward ]; then
    tr -d '\r\n' < /proc/sys/net/ipv4/ip_forward
  else
    return 1
  fi
}

ztg_exit_node_sysctl_content() {
  cat <<EOF
# Managed-By: ${ZTG_EXIT_NODE_MARKER}
# This file enables IPv4 forwarding for the ZeroTier Gateway private Exit Node.
net.ipv4.ip_forward=1
EOF
}

ztg_exit_node_file_owned() {
  local path="$1"
  [ -f "$path" ] && grep -Fqx "# Managed-By: ${ZTG_EXIT_NODE_MARKER}" "$path"
}

ztg_exit_node_print_rule_plan() {
  local zerotier_subnet="$1" zt_iface="$2" wan_iface="$3"
  printf 'sysctl -w net.ipv4.ip_forward=1\n'
  printf 'iptables -t nat -A POSTROUTING -s %s -o %s -m comment --comment %s -j MASQUERADE\n' "$zerotier_subnet" "$wan_iface" "$ZTG_EXIT_NODE_NAT_COMMENT"
  printf 'iptables -I FORWARD 1 -i %s -o %s -s %s -m conntrack --ctstate NEW,ESTABLISHED,RELATED -m comment --comment %s -j ACCEPT\n' "$zt_iface" "$wan_iface" "$zerotier_subnet" "$ZTG_EXIT_NODE_FORWARD_OUT_COMMENT"
  printf 'iptables -I FORWARD 1 -i %s -o %s -d %s -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment %s -j ACCEPT\n' "$wan_iface" "$zt_iface" "$zerotier_subnet" "$ZTG_EXIT_NODE_FORWARD_IN_COMMENT"
}

ztg_exit_node_nat_exists() {
  local zerotier_subnet="$1" wan_iface="$2"
  iptables -t nat -C POSTROUTING -s "$zerotier_subnet" -o "$wan_iface" -m comment --comment "$ZTG_EXIT_NODE_NAT_COMMENT" -j MASQUERADE >/dev/null 2>&1
}

ztg_exit_node_forward_out_exists() {
  local zerotier_subnet="$1" zt_iface="$2" wan_iface="$3"
  iptables -C FORWARD -i "$zt_iface" -o "$wan_iface" -s "$zerotier_subnet" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_OUT_COMMENT" -j ACCEPT >/dev/null 2>&1
}

ztg_exit_node_forward_in_exists() {
  local zerotier_subnet="$1" zt_iface="$2" wan_iface="$3"
  iptables -C FORWARD -i "$wan_iface" -o "$zt_iface" -d "$zerotier_subnet" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_IN_COMMENT" -j ACCEPT >/dev/null 2>&1
}

ztg_exit_node_apply_rules() {
  local zerotier_subnet="$1" zt_iface="$2" wan_iface="$3"
  if ! ztg_exit_node_nat_exists "$zerotier_subnet" "$wan_iface"; then
    iptables -t nat -A POSTROUTING -s "$zerotier_subnet" -o "$wan_iface" -m comment --comment "$ZTG_EXIT_NODE_NAT_COMMENT" -j MASQUERADE
  fi
  if ! ztg_exit_node_forward_out_exists "$zerotier_subnet" "$zt_iface" "$wan_iface"; then
    iptables -I FORWARD 1 -i "$zt_iface" -o "$wan_iface" -s "$zerotier_subnet" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_OUT_COMMENT" -j ACCEPT
  fi
  if ! ztg_exit_node_forward_in_exists "$zerotier_subnet" "$zt_iface" "$wan_iface"; then
    iptables -I FORWARD 1 -i "$wan_iface" -o "$zt_iface" -d "$zerotier_subnet" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_IN_COMMENT" -j ACCEPT
  fi
}

ztg_exit_node_remove_rules() {
  local zerotier_subnet="$1" zt_iface="$2" wan_iface="$3" failed=false
  while ztg_exit_node_nat_exists "$zerotier_subnet" "$wan_iface"; do
    iptables -t nat -D POSTROUTING -s "$zerotier_subnet" -o "$wan_iface" -m comment --comment "$ZTG_EXIT_NODE_NAT_COMMENT" -j MASQUERADE || failed=true
    $failed && break
  done
  while ztg_exit_node_forward_out_exists "$zerotier_subnet" "$zt_iface" "$wan_iface"; do
    iptables -D FORWARD -i "$zt_iface" -o "$wan_iface" -s "$zerotier_subnet" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_OUT_COMMENT" -j ACCEPT || failed=true
    $failed && break
  done
  while ztg_exit_node_forward_in_exists "$zerotier_subnet" "$zt_iface" "$wan_iface"; do
    iptables -D FORWARD -i "$wan_iface" -o "$zt_iface" -d "$zerotier_subnet" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "$ZTG_EXIT_NODE_FORWARD_IN_COMMENT" -j ACCEPT || failed=true
    $failed && break
  done
  ! $failed
}

ztg_exit_node_assert_system_tools() {
  local required missing=0
  for required in ip sysctl iptables systemctl; do
    if ! command -v "$required" >/dev/null 2>&1; then
      ztg_log_error "$required is required to manage the private Exit Node."
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ]
}

ztg_exit_node_write_sysctl_file() {
  local target="$1"
  if [ -e "$target" ] && ! ztg_exit_node_file_owned "$target"; then
    ztg_log_error "Existing sysctl file is not owned by this project: $target"
    return 1
  fi
  ztg_atomic_write "$target" "$(ztg_exit_node_sysctl_content)" 0644
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

ztg_exit_node_remove_sysctl_file() {
  local target="$1"
  if [ ! -e "$target" ]; then
    return 0
  fi
  ztg_exit_node_file_owned "$target" || {
    ztg_log_error "Sysctl file ownership mismatch: $target"
    return 1
  }
  rm -f "$target"
}

ztg_exit_node_forwarding_requested_elsewhere() {
  local project_sysctl="$1" candidate
  for candidate in /etc/sysctl.conf /etc/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /run/sysctl.d/*.conf; do
    [ -f "$candidate" ] || continue
    [ "$candidate" = "$project_sysctl" ] && continue
    if grep -Eq '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1([[:space:]]*(#.*)?)?$' "$candidate"; then
      return 0
    fi
  done
  return 1
}

ztg_exit_node_maybe_restore_forwarding_zero() {
  local previous_runtime="$1" project_sysctl="$2"
  [ "$previous_runtime" = "0" ] || return 0
  if ztg_exit_node_forwarding_requested_elsewhere "$project_sysctl"; then
    ztg_log_warn "IPv4 forwarding is still requested by another sysctl file; runtime forwarding was left unchanged."
    return 0
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -w net.ipv4.ip_forward=0 >/dev/null || return 1
  fi
}

ztg_exit_node_render_restore_unit() {
  local manager_path="$1" template content
  template="$(<"$ZTG_ROOT/templates/systemd/zerotier-gateway-exit-node.service.tmpl")"
  content="${template//\{\{EXIT_NODE_MANAGER_PATH\}\}/$manager_path}"
  printf '%s\n' "$content"
}

ztg_exit_node_install_restore_unit() {
  local manager_path="$1" unit_path="$2" content temporary
  if [ -e "$unit_path" ] && ! ztg_exit_node_file_owned "$unit_path"; then
    ztg_log_error "Existing restore unit is not owned by this project: $unit_path"
    return 1
  fi
  content="$(ztg_exit_node_render_restore_unit "$manager_path")"
  install -d -m 0755 "$(dirname "$unit_path")" || return 1
  temporary="$(mktemp "$(dirname "$unit_path")/.ztg-exit-node-unit.XXXXXX")" || return 1
  printf '%s\n' "$content" > "$temporary" || return 1
  chmod 0644 "$temporary" || return 1
  mv -f "$temporary" "$unit_path" || return 1
  systemctl daemon-reload || return 1
  systemctl enable "$ZTG_EXIT_NODE_UNIT_NAME" >/dev/null || return 1
}

ztg_exit_node_remove_restore_unit() {
  local unit_path="$1"
  if [ ! -e "$unit_path" ]; then
    return 0
  fi
  ztg_exit_node_file_owned "$unit_path" || {
    ztg_log_error "Restore unit ownership mismatch: $unit_path"
    return 1
  }
  systemctl disable --now "$ZTG_EXIT_NODE_UNIT_NAME" >/dev/null 2>&1 || return 1
  rm -f "$unit_path" || return 1
  systemctl daemon-reload || return 1
}

ztg_exit_node_write_state() {
  local path="$1" enabled="$2" zerotier_subnet="$3" ubuntu_zt_ip="$4" zt_iface="$5" wan_iface="$6" previous_runtime="$7" generation="$8" sysctl_file="$9" restore_unit="${10}"
  local nat_digest forward_out_digest forward_in_digest sysctl_hash unit_hash json
  nat_digest="$(ztg_exit_node_sha256_text "nat|POSTROUTING|${zerotier_subnet}|${wan_iface}|${ZTG_EXIT_NODE_NAT_COMMENT}")"
  forward_out_digest="$(ztg_exit_node_sha256_text "filter|FORWARD|${zt_iface}|${wan_iface}|${zerotier_subnet}|${ZTG_EXIT_NODE_FORWARD_OUT_COMMENT}")"
  forward_in_digest="$(ztg_exit_node_sha256_text "filter|FORWARD|${wan_iface}|${zt_iface}|${zerotier_subnet}|${ZTG_EXIT_NODE_FORWARD_IN_COMMENT}")"
  sysctl_hash="$(ztg_sha256_file "$sysctl_file")"
  unit_hash="$(ztg_sha256_file "$restore_unit")"
  json=$(cat <<JSON
{
  "schemaVersion": ${ZTG_STATE_SCHEMA_VERSION},
  "objectVersion": 1,
  "owner": "${ZTG_STATE_OWNER}",
  "objectType": "exit-node",
  "objectName": "${ZTG_EXIT_NODE_OBJECT_NAME}",
  "enabled": ${enabled},
  "lastAppliedVersion": "$(ztg_json_escape "$(ztg_project_version)")",
  "generation": ${generation},
  "zerotierSubnet": "$(ztg_json_escape "$zerotier_subnet")",
  "ubuntuZtIp": "$(ztg_json_escape "$ubuntu_zt_ip")",
  "ztInterface": "$(ztg_json_escape "$zt_iface")",
  "wanInterface": "$(ztg_json_escape "$wan_iface")",
  "rules": [
    { "table": "nat", "chain": "POSTROUTING", "comment": "${ZTG_EXIT_NODE_NAT_COMMENT}", "renderedDigest": "${nat_digest}" },
    { "table": "filter", "chain": "FORWARD", "comment": "${ZTG_EXIT_NODE_FORWARD_OUT_COMMENT}", "renderedDigest": "${forward_out_digest}" },
    { "table": "filter", "chain": "FORWARD", "comment": "${ZTG_EXIT_NODE_FORWARD_IN_COMMENT}", "renderedDigest": "${forward_in_digest}" }
  ],
  "sysctlFile": { "path": "$(ztg_json_escape "$sysctl_file")", "hash": "$(ztg_json_escape "$sysctl_hash")" },
  "restoreUnit": { "path": "$(ztg_json_escape "$restore_unit")", "hash": "$(ztg_json_escape "$unit_hash")" },
  "previousRuntimeForwarding": "$(ztg_json_escape "$previous_runtime")",
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
)
  ztg_atomic_write "$path" "$json" 0600
}
