#!/usr/bin/env bash

ztg_firewall_proxy_preview() {
  ztg_log_step "Firewall rule preview"
  ztg_log_info "Allow ${ZEROTIER_SUBNET} to ${PROXY_BIND_IP}:${PROXY_PORT}"
  if ztg_is_true "${PROXY_PUBLIC_ACCESS:-false}"; then
    ztg_log_warn "Public proxy entry is enabled. Proxy authentication remains optional."
    if [ -n "${PROXY_ALLOWED_CLIENT_CIDRS:-}" ]; then
      ztg_log_info "Allow public clients: ${PROXY_ALLOWED_CLIENT_CIDRS}"
    else
      ztg_log_warn "No PROXY_ALLOWED_CLIENT_CIDRS configured. Public proxy access will allow all source IPs."
    fi
  else
    ztg_log_info "Do not expose ${PROXY_PORT} to public interfaces."
  fi
}

ztg_apply_firewall_proxy() {
  ztg_firewall_proxy_preview
  if command -v ufw >/dev/null 2>&1; then
    ztg_run ufw allow from "$ZEROTIER_SUBNET" to any port "$PROXY_PORT" proto tcp comment ztg-proxy-allow
    if ztg_is_true "${PROXY_PUBLIC_ACCESS:-false}" && [ -n "${PROXY_ALLOWED_CLIENT_CIDRS:-}" ]; then
      ztg_run ufw delete allow to any port "$PROXY_PORT" proto tcp || true
      local cidr
      local -a ztg_proxy_allowed_cidrs
      IFS=',' read -r -a ztg_proxy_allowed_cidrs <<< "$PROXY_ALLOWED_CLIENT_CIDRS"
      for cidr in "${ztg_proxy_allowed_cidrs[@]}"; do
        cidr="$(ztg_trim "$cidr")"
        [ -n "$cidr" ] || continue
        ztg_run ufw allow from "$cidr" to any port "$PROXY_PORT" proto tcp comment ztg-proxy-public-allow
      done
    elif ztg_is_true "${PROXY_PUBLIC_ACCESS:-false}"; then
      ztg_run ufw allow to any port "$PROXY_PORT" proto tcp comment ztg-proxy-public-allow
    else
      ztg_run ufw delete allow to any port "$PROXY_PORT" proto tcp || true
    fi
  else
    ztg_log_warn "ufw not found. Apply equivalent firewall rule manually if needed."
  fi
}

# Opt-in: allow ZeroTier's UDP 9993 inbound so peers can establish DIRECT paths.
# Without it, a default-deny ufw can force phone/peer traffic onto slow RELAY paths.
# Default OFF; when disabled this function changes nothing. ufw adds v4 and v6 rules
# and skips duplicates, so re-running is idempotent.
ztg_apply_firewall_zerotier_udp() {
  if ! ztg_is_true "${ZEROTIER_ALLOW_UDP_INBOUND:-false}"; then
    return 0
  fi
  ztg_log_step "ZeroTier UDP inbound"
  ztg_log_info "Allow inbound 9993/udp for ZeroTier DIRECT peer paths."
  if command -v ufw >/dev/null 2>&1; then
    ztg_run ufw allow 9993/udp comment zerotier
  else
    ztg_log_warn "ufw not found. Allow inbound UDP 9993 manually if a firewall blocks it."
  fi
}
