#!/usr/bin/env bash

ztg_validate_tcp_port() {
  local port="$1"
  local label="$2"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    ztg_log_error "$label must be a TCP port between 1 and 65535: $port"
    exit 1
  fi
}

ztg_relay_remote_ports() {
  local raw port
  local -a raw_ports
  IFS=',' read -r -a raw_ports <<< "${REMOTE_PORTS:-3389}"
  for raw in "${raw_ports[@]}"; do
    port="$(ztg_trim "$raw")"
    [ -n "$port" ] || continue
    ztg_validate_tcp_port "$port" "REMOTE_PORTS"
    printf '%s\n' "$port"
  done
}

ztg_find_socket_proxyd() {
  local candidate
  for candidate in \
    "$(command -v systemd-socket-proxyd 2>/dev/null || true)" \
    /usr/lib/systemd/systemd-socket-proxyd \
    /lib/systemd/systemd-socket-proxyd; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

ztg_relay_unit_name() {
  local side="$1"
  local remote_port="$2"
  printf 'zerotier-gateway-relay-%s-%s' "$side" "$remote_port"
}

ztg_relay_print_entry() {
  local side="$1"
  local listen_port="$2"
  local target_ip="$3"
  local remote_port="$4"
  local label="$5"
  ztg_log_info "${label}: ${UBUNTU_ZT_IP}:${listen_port} -> ${target_ip}:${remote_port}"
}

ztg_relay_preview() {
  ztg_log_step "Relay preview"
  ztg_log_info "Relay is optional and should be enabled only when DIRECT is poor."
  ztg_validate_tcp_port "${RELAY_PORT}" "RELAY_PORT"

  local index=0
  local remote_port home_listen work_listen
  while IFS= read -r remote_port; do
    home_listen=$((RELAY_PORT + index * 2))
    work_listen=$((RELAY_PORT + index * 2 + 1))
    ztg_validate_tcp_port "$home_listen" "home relay listen port"
    ztg_validate_tcp_port "$work_listen" "work relay listen port"
    ztg_relay_print_entry "home" "$home_listen" "$HOME_PC_ZT_IP" "$remote_port" "Company connects here to reach Home"
    ztg_relay_print_entry "work" "$work_listen" "$WORK_PC_ZT_IP" "$remote_port" "Home connects here to reach Work"
    index=$((index + 1))
  done < <(ztg_relay_remote_ports)

  if [ "$index" -eq 0 ]; then
    ztg_log_error "REMOTE_PORTS must include at least one TCP port."
    exit 1
  fi
}

ztg_write_relay_unit() {
  local template="$1"
  local target="$2"
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    printf '[DRY-RUN] write %s\n' "$target"
    return 0
  fi
  ztg_render_template "$template" "$target"
}

ztg_remove_generated_relay_units() {
  local pattern unit_file unit
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    printf '[DRY-RUN] remove any /etc/systemd/system/zerotier-gateway-relay-*.socket\n'
    printf '[DRY-RUN] remove any /etc/systemd/system/zerotier-gateway-relay-*.service\n'
    return 0
  fi

  for pattern in \
    /etc/systemd/system/zerotier-gateway-relay-*.socket \
    /etc/systemd/system/zerotier-gateway-relay-*.service; do
    for unit_file in $pattern; do
      [ -e "$unit_file" ] || continue
      unit="$(basename "$unit_file")"
      systemctl disable --now "$unit" >/dev/null 2>&1 || true
      rm -f "$unit_file"
    done
  done
}

ztg_install_relay_entry() {
  local side="$1"
  local listen_port="$2"
  local target_ip="$3"
  local remote_port="$4"
  local label="$5"

  local unit
  unit="$(ztg_relay_unit_name "$side" "$remote_port")"

  local RELAY_UNIT_DESCRIPTION RELAY_SOCKET_UNIT RELAY_LISTEN RELAY_TARGET
  RELAY_UNIT_DESCRIPTION="ZeroTier Gateway relay ${label} ${remote_port}"
  RELAY_SOCKET_UNIT="${unit}.socket"
  RELAY_LISTEN="${UBUNTU_ZT_IP}:${listen_port}"
  RELAY_TARGET="${target_ip}:${remote_port}"

  ztg_write_relay_unit \
    "$ZTG_ROOT/templates/systemd/zerotier-tcp-relay.socket.tmpl" \
    "/etc/systemd/system/${unit}.socket"
  ztg_write_relay_unit \
    "$ZTG_ROOT/templates/systemd/zerotier-tcp-relay.service.tmpl" \
    "/etc/systemd/system/${unit}.service"
}

ztg_enable_relay_entry() {
  local side="$1"
  local remote_port="$2"
  local unit
  unit="$(ztg_relay_unit_name "$side" "$remote_port")"
  ztg_run systemctl enable --now "${unit}.socket"
}

ztg_install_relay() {
  ztg_relay_preview

  local SOCKET_PROXYD_PATH
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    SOCKET_PROXYD_PATH="/usr/lib/systemd/systemd-socket-proxyd"
  elif ! SOCKET_PROXYD_PATH="$(ztg_find_socket_proxyd)"; then
    ztg_log_error "systemd-socket-proxyd was not found. This relay installer requires a systemd-based Ubuntu server."
    exit 1
  fi

  if [ "${ZTG_DRY_RUN:-false}" != "true" ] && ! command -v systemctl >/dev/null 2>&1; then
    ztg_log_error "systemctl was not found. This relay installer requires systemd."
    exit 1
  fi

  ztg_remove_generated_relay_units
  ztg_run install -d -m 0755 /etc/systemd/system

  local index=0
  local remote_port home_listen work_listen
  while IFS= read -r remote_port; do
    home_listen=$((RELAY_PORT + index * 2))
    work_listen=$((RELAY_PORT + index * 2 + 1))
    ztg_install_relay_entry "home" "$home_listen" "$HOME_PC_ZT_IP" "$remote_port" "to Home"
    ztg_install_relay_entry "work" "$work_listen" "$WORK_PC_ZT_IP" "$remote_port" "to Work"
    index=$((index + 1))
  done < <(ztg_relay_remote_ports)

  ztg_run systemctl daemon-reload

  while IFS= read -r remote_port; do
    ztg_enable_relay_entry "home" "$remote_port"
    ztg_enable_relay_entry "work" "$remote_port"
  done < <(ztg_relay_remote_ports)

  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    ztg_log_info "Dry-run complete. No relay service was installed."
  else
    ztg_log_info "Relay sockets installed. Connect through the Ubuntu ZeroTier IP shown above."
  fi
}

ztg_disable_unit_if_exists() {
  local unit="$1"
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    printf '[DRY-RUN] systemctl disable --now %s\n' "$unit"
    return 0
  fi
  systemctl disable --now "$unit" >/dev/null 2>&1 || true
}

ztg_remove_file_if_exists() {
  local path="$1"
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    printf '[DRY-RUN] rm -f %s\n' "$path"
    return 0
  fi
  rm -f "$path"
}

ztg_disable_relay() {
  ztg_log_step "Disable optional relay"

  local remote_port unit
  while IFS= read -r remote_port; do
    for side in home work; do
      unit="$(ztg_relay_unit_name "$side" "$remote_port")"
      ztg_disable_unit_if_exists "${unit}.socket"
      ztg_disable_unit_if_exists "${unit}.service"
      ztg_remove_file_if_exists "/etc/systemd/system/${unit}.socket"
      ztg_remove_file_if_exists "/etc/systemd/system/${unit}.service"
    done
  done < <(ztg_relay_remote_ports)

  ztg_disable_unit_if_exists "zerotier-tcp-relay.service"
  ztg_remove_file_if_exists "/etc/systemd/system/zerotier-tcp-relay.service"
  ztg_remove_generated_relay_units
  ztg_run systemctl daemon-reload
  ztg_log_info "Relay disabled. ZeroTier DIRECT remains preferred."
}
