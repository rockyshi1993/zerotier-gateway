#!/usr/bin/env bash

ztg_firewall_proxy_preview() {
  ztg_log_step "Firewall rule preview"
  ztg_log_info "Allow ${ZEROTIER_SUBNET} to ${PROXY_BIND_IP}:${PROXY_PORT}"
  ztg_log_info "Do not expose ${PROXY_PORT} to public interfaces."
}

ztg_apply_firewall_proxy() {
  ztg_firewall_proxy_preview
  if command -v ufw >/dev/null 2>&1; then
    ztg_run ufw allow from "$ZEROTIER_SUBNET" to any port "$PROXY_PORT" proto tcp comment ztg-proxy-allow
  else
    ztg_log_warn "ufw not found. Apply equivalent firewall rule manually if needed."
  fi
}
