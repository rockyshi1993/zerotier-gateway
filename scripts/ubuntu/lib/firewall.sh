#!/usr/bin/env bash

ztg_firewall_proxy_preview() {
  ztg_log_step "Firewall rule preview"
  ztg_log_info "Allow ${ZEROTIER_SUBNET} to ${PROXY_BIND_IP}:${PROXY_PORT}"
  if ztg_is_true "${PROXY_PUBLIC_ACCESS:-false}"; then
    ztg_log_warn "Public proxy entry is enabled. Proxy authentication remains optional, but source IPs must be restricted by firewall rules."
    if [ -n "${PROXY_ALLOWED_CLIENT_CIDRS:-}" ]; then
      ztg_log_info "Allow public clients: ${PROXY_ALLOWED_CLIENT_CIDRS}"
    else
      ztg_log_warn "No PROXY_ALLOWED_CLIENT_CIDRS configured. The script will not add a broad public allow rule."
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
      local cidr
      local -a ztg_proxy_allowed_cidrs
      IFS=',' read -r -a ztg_proxy_allowed_cidrs <<< "$PROXY_ALLOWED_CLIENT_CIDRS"
      for cidr in "${ztg_proxy_allowed_cidrs[@]}"; do
        cidr="$(ztg_trim "$cidr")"
        [ -n "$cidr" ] || continue
        ztg_run ufw allow from "$cidr" to any port "$PROXY_PORT" proto tcp comment ztg-proxy-public-allow
      done
    fi
  else
    ztg_log_warn "ufw not found. Apply equivalent firewall rule manually if needed."
  fi
}
